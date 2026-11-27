/**
 * 保险库导入 / 导出（.json 与 .csv）。
 *
 * 导出格式与 Bitwarden 未加密导出保持一致，导入时也按该格式解析：
 *  - JSON：{ encrypted:false, folders:[{id,name}], items:[{type,name,notes,favorite,folderId,login:{username,password,totp,uris},fields}] }
 *  - CSV ：folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
 *
 * 文件读写走系统文件选择器（用户自己选位置），应用不申请存储权限。
 */
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { VaultStore } from './VaultStore';
import { CipherDraft, CipherType, VaultField, VaultItem, emptyCard, emptyIdentity, emptyDraft } from './Models';

/** 用户选中的文件 */
export interface PickedFile {
  name: string;
  text: string;
}

/** 导出/导入结果 */
export interface IoResult {
  /** 成功条数 */
  imported: number;
  /** 跳过条数（缺名称等） */
  skipped: number;
  /** 新建的文件夹数 */
  folders: number;
}

interface IoUri {
  uri?: string | null;
}

interface IoLogin {
  username?: string | null;
  password?: string | null;
  totp?: string | null;
  uri?: string | null;
  uris?: IoUri[] | null;
}

interface IoField {
  name?: string | null;
  value?: string | null;
  type?: number | null;
}

interface IoItem {
  type?: number | null;
  name?: string | null;
  notes?: string | null;
  favorite?: boolean | null;
  folderId?: string | null;
  login?: IoLogin | null;
  fields?: IoField[] | null;
}

interface IoFolder {
  id?: string | null;
  name?: string | null;
}

interface IoVault {
  encrypted?: boolean | null;
  folders?: IoFolder[] | null;
  items?: IoItem[] | null;
}

/** CSV 转义：含逗号、引号、换行时整体加引号，内部引号双写 */
function csvCell(value: string): string {
  const text: string = value === undefined || value === null ? '' : value;
  if (text.indexOf(',') >= 0 || text.indexOf('"') >= 0 || text.indexOf('\n') >= 0 || text.indexOf('\r') >= 0) {
    return '"' + text.split('"').join('""') + '"';
  }
  return text;
}

/** 解析一行 CSV（支持引号包裹与双写引号） */
function splitCsvLine(line: string): string[] {
  const out: string[] = [];
  let cell: string = '';
  let quoted: boolean = false;
  for (let i = 0; i < line.length; i++) {
    const ch: string = line.charAt(i);
    if (quoted) {
      if (ch === '"') {
        if (i + 1 < line.length && line.charAt(i + 1) === '"') {
          cell += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ',') {
      out.push(cell);
      cell = '';
    } else {
      cell += ch;
    }
  }
  out.push(cell);
  return out;
}

/** 把文本拆成 CSV 行，处理引号内的换行 */
function splitCsvRows(text: string): string[] {
  const rows: string[] = [];
  let row: string = '';
  let quoted: boolean = false;
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (ch === '"') {
      quoted = !quoted;
      row += ch;
    } else if ((ch === '\n' || ch === '\r') && !quoted) {
      if (row.length > 0) {
        rows.push(row);
        row = '';
      }
    } else {
      row += ch;
    }
  }
  if (row.length > 0) {
    rows.push(row);
  }
  return rows;
}

function typeName(type: number): string {
  return type === CipherType.Card ? 'card' : (type === CipherType.Identity ? 'identity' :
    (type === CipherType.SecureNote ? 'note' : 'login'));
}

function typeFromText(text: string): number {
  const t: string = text.trim().toLowerCase();
  if (t === 'card' || t === '3') {
    return CipherType.Card;
  }
  if (t === 'identity' || t === '4') {
    return CipherType.Identity;
  }
  if (t === 'note' || t === 'securenote' || t === '2') {
    return CipherType.SecureNote;
  }
  return CipherType.Login;
}

export class VaultIO {
  /** 生成 JSON 导出文本 */
  static exportJson(): string {
    const folders: IoFolder[] = [];
    for (let i = 0; i < VaultStore.folders.length; i++) {
      folders.push({ id: VaultStore.folders[i].id, name: VaultStore.folders[i].name });
    }
    const items: IoItem[] = [];
    for (let i = 0; i < VaultStore.items.length; i++) {
      const it: VaultItem = VaultStore.items[i];
      const uris: IoUri[] = [];
      if (it.uri.length > 0) {
        uris.push({ uri: it.uri });
      }
      const fields: IoField[] = [];
      const srcFields: VaultField[] | null = it.fields === undefined || it.fields === null ? null : it.fields;
      if (srcFields !== null) {
        for (let k = 0; k < srcFields.length; k++) {
          fields.push({ name: srcFields[k].name, value: srcFields[k].value, type: srcFields[k].type });
        }
      }
      items.push({
        type: it.type,
        name: it.name,
        notes: it.notes,
        favorite: it.favorite,
        folderId: it.folderId,
        login: {
          username: it.username,
          password: it.password,
          totp: it.totp,
          uri: it.uri,
          uris: uris
        },
        fields: fields
      });
    }
    const vault: IoVault = { encrypted: false, folders: folders, items: items };
    return JSON.stringify(vault, null, 2);
  }

  /** 生成 Bitwarden 兼容 CSV 文本 */
  static exportCsv(): string {
    const folderName: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < VaultStore.folders.length; i++) {
      folderName.set(VaultStore.folders[i].id, VaultStore.folders[i].name);
    }
    const lines: string[] = ['folder,favorite,type,name,notes,fields,reprompt,login_uri,' +
      'login_username,login_password,login_totp'];
    for (let i = 0; i < VaultStore.items.length; i++) {
      const it: VaultItem = VaultStore.items[i];
      const folder: string = folderName.has(it.folderId) ? folderName.get(it.folderId) as string : '';
      let fields: string = '';
      const csvFields: VaultField[] | null = it.fields === undefined || it.fields === null ? null : it.fields;
      if (csvFields !== null && csvFields.length > 0) {
        const parts: string[] = [];
        for (let k = 0; k < csvFields.length; k++) {
          parts.push(`${csvFields[k].name}: ${csvFields[k].value}`);
        }
        fields = parts.join('\n');
      }
      lines.push([
        csvCell(folder),
        csvCell(it.favorite ? '1' : ''),
        csvCell(typeName(it.type)),
        csvCell(it.name),
        csvCell(it.notes),
        csvCell(fields),
        csvCell(''),
        csvCell(it.uri),
        csvCell(it.username),
        csvCell(it.password),
        csvCell(it.totp)
      ].join(','));
    }
    return lines.join('\r\n');
  }

  /** 解析并导入 JSON / CSV 文本（按文件名后缀调用方决定） */
  static async importText(text: string, csv: boolean): Promise<IoResult> {
    if (csv) {
      return VaultIO.importCsv(text);
    }
    return VaultIO.importJson(text);
  }

  private static async importJson(text: string): Promise<IoResult> {
    const vault: IoVault = JSON.parse(text) as IoVault;
    if (vault.encrypted === true) {
      throw new Error('这是加密导出文件，请在 Bitwarden 里选择「未加密导出」后重试');
    }
    const folders: IoFolder[] = vault.folders === undefined || vault.folders === null ? [] : vault.folders;
    const items: IoItem[] = vault.items === undefined || vault.items === null ? [] : vault.items;
    const folderIds: Map<string, string> = new Map<string, string>();
    let createdFolders: number = 0;
    for (let i = 0; i < folders.length; i++) {
      const f: IoFolder = folders[i];
      const name: string = f.name === undefined || f.name === null ? '' : f.name;
      if (name.length === 0) {
        continue;
      }
      const id: string = await VaultIO.ensureFolder(name);
      if (id.length > 0) {
        folderIds.set(f.id === undefined || f.id === null ? '' : f.id, id);
        createdFolders++;
      }
    }
    let imported: number = 0;
    let skipped: number = 0;
    for (let i = 0; i < items.length; i++) {
      const it: IoItem = items[i];
      const name: string = it.name === undefined || it.name === null ? '' : it.name;
      if (name.trim().length === 0) {
        skipped++;
        continue;
      }
      const folderKey: string = it.folderId === undefined || it.folderId === null ? '' : it.folderId;
      const folderId: string = folderIds.has(folderKey) ? folderIds.get(folderKey) as string : '';
      await VaultIO.importOne(name, it.type === undefined || it.type === null ? 1 : it.type,
        it.notes, it.favorite === true, folderId, it.login, it.fields);
      imported++;
    }
    return { imported: imported, skipped: skipped, folders: createdFolders };
  }

  private static async importCsv(text: string): Promise<IoResult> {
    const rows: string[] = splitCsvRows(text);
    if (rows.length === 0) {
      throw new Error('文件是空的');
    }
    const header: string[] = splitCsvLine(rows[0]).map((cell: string) => cell.trim().toLowerCase());
    const idxFolder: number = header.indexOf('folder');
    const idxFavorite: number = header.indexOf('favorite');
    const idxType: number = header.indexOf('type');
    const idxName: number = header.indexOf('name');
    const idxNotes: number = header.indexOf('notes');
    const idxFields: number = header.indexOf('fields');
    const idxUri: number = header.indexOf('login_uri');
    const idxUser: number = header.indexOf('login_username');
    const idxPass: number = header.indexOf('login_password');
    const idxTotp: number = header.indexOf('login_totp');
    if (idxName < 0) {
      throw new Error('CSV 缺少 name 列，无法识别为 Bitwarden 导出文件');
    }
    let imported: number = 0;
    let skipped: number = 0;
    let createdFolders: number = 0;
    const folderCache: Map<string, string> = new Map<string, string>();
    for (let r = 1; r < rows.length; r++) {
      const cells: string[] = splitCsvLine(rows[r]);
      const cell = (index: number): string => {
        if (index < 0 || index >= cells.length) {
          return '';
        }
        return cells[index];
      };
      const name: string = cell(idxName);
      if (name.trim().length === 0) {
        skipped++;
        continue;
      }
      let folderId: string = '';
      const folderName: string = cell(idxFolder).trim();
      if (folderName.length > 0) {
        if (folderCache.has(folderName)) {
          folderId = folderCache.get(folderName) as string;
        } else {
          folderId = await VaultIO.ensureFolder(folderName);
          folderCache.set(folderName, folderId);
          createdFolders++;
        }
      }
      const fields: IoField[] = [];
      const rawFields: string = cell(idxFields);
      if (rawFields.length > 0) {
        const lines: string[] = rawFields.split('\n');
        for (let k = 0; k < lines.length; k++) {
          const line: string = lines[k];
          const at: number = line.indexOf(':');
          if (at > 0) {
            fields.push({ name: line.substring(0, at).trim(), value: line.substring(at + 1).trim(), type: 0 });
          }
        }
      }
      const login: IoLogin = {
        username: cell(idxUser),
        password: cell(idxPass),
        totp: cell(idxTotp),
        uri: cell(idxUri),
        uris: cell(idxUri).length > 0 ? [{ uri: cell(idxUri) }] : null
      };
      await VaultIO.importOne(name, typeFromText(cell(idxType)), cell(idxNotes),
        cell(idxFavorite).trim() === '1' || cell(idxFavorite).trim().toLowerCase() === 'true',
        folderId, login, fields);
      imported++;
    }
    return { imported: imported, skipped: skipped, folders: createdFolders };
  }

  /** 按名字找文件夹，没有就建；返回 id */
  private static async ensureFolder(name: string): Promise<string> {
    for (let i = 0; i < VaultStore.folders.length; i++) {
      if (VaultStore.folders[i].name === name) {
        return VaultStore.folders[i].id;
      }
    }
    return await VaultStore.createFolder(name);
  }

  private static async importOne(name: string, type: number, notes: string | null | undefined,
    favorite: boolean, folderId: string, login: IoLogin | null | undefined,
    fields: IoField[] | null | undefined): Promise<void> {
    const draft: CipherDraft = emptyDraft(CipherType.Login);
    draft.id = '';
    draft.name = name;
    draft.type = type;
    draft.notes = notes === undefined || notes === null ? '' : notes;
    draft.favorite = favorite;
    draft.folderId = folderId;
    if (type === CipherType.Login && login !== undefined && login !== null) {
      draft.username = login.username === undefined || login.username === null ? '' : login.username;
      draft.password = login.password === undefined || login.password === null ? '' : login.password;
      draft.totp = login.totp === undefined || login.totp === null ? '' : login.totp;
      let uri: string = login.uri === undefined || login.uri === null ? '' : login.uri;
      if (uri.length === 0 && login.uris !== undefined && login.uris !== null && login.uris.length > 0) {
        const first: IoUri = login.uris[0];
        uri = first.uri === undefined || first.uri === null ? '' : first.uri;
      }
      draft.uri = uri;
    }
    const list: VaultField[] = [];
    if (fields !== undefined && fields !== null) {
      for (let i = 0; i < fields.length; i++) {
        const f: IoField = fields[i];
        const fieldName: string = f.name === undefined || f.name === null ? '' : f.name;
        const fieldValue: string = f.value === undefined || f.value === null ? '' : f.value;
        if (fieldName.length === 0 && fieldValue.length === 0) {
          continue;
        }
        list.push({ name: fieldName, value: fieldValue, type: f.type === undefined || f.type === null ? 0 : f.type });
      }
    }
    draft.fields = list;
    draft.card = emptyCard();
    draft.identity = emptyIdentity();
    await VaultStore.saveDraft(draft);
  }

  /** 弹出系统保存框，把文本写进用户选择的位置；返回文件名（取消返回空串） */
  static async saveToFile(defaultName: string, content: string): Promise<string> {
    const context = VaultStore.appContext();
    if (context === null) {
      throw new Error('应用上下文未就绪');
    }
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [defaultName];
    const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await viewPicker.save(options);
    if (uris === undefined || uris === null || uris.length === 0) {
      return '';
    }
    const file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, content);
    fs.closeSync(file);
    return defaultName;
  }

  /** 弹出系统文件选择框，读取文本；取消返回 name 为空的对象 */
  static async pickFile(): Promise<PickedFile> {
    const context = VaultStore.appContext();
    if (context === null) {
      throw new Error('应用上下文未就绪');
    }
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await viewPicker.select(options);
    if (uris === undefined || uris === null || uris.length === 0) {
      return { name: '', text: '' };
    }
    const uri: string = uris[0];
    const slash: number = uri.lastIndexOf('/');
    const rawName: string = slash >= 0 ? uri.substring(slash + 1) : uri;
    const name: string = decodeURIComponent(rawName);
    // 选择器给出的是 file://docs/... 这类 URI，readTextSync 只接受普通路径，
    // 因此先按 URI 打开拿 fd，再按大小读出来解码。
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const size: number = fs.statSync(file.fd).size;
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    fs.readSync(file.fd, buffer);
    fs.closeSync(file);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const text: string = decoder.decodeToString(new Uint8Array(buffer));
    return { name: name, text: text };
  }

  /** 根据文件名判断是否 CSV */
  static isCsvName(name: string): boolean {
    return name.toLowerCase().endsWith('.csv');
  }
}
