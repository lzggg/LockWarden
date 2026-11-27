/**
 * 演示数据：不连接任何服务器也能看到完整界面与交互。
 * 仅用于 UI 预览 / 首次体验，数据不加密、不落盘、不联网。
 *
 * 其中「公司 VPN」带一个真实可用的 TOTP 密钥（Base32: JBSWY3DPEHPK3PXP），
 * 详情页会显示每 30 秒刷新的 6 位动态码。
 */
import { VaultItem, VaultFolder } from './Models';

export function demoItems(): VaultItem[] {
  const items: VaultItem[] = [
    {
      id: 'demo-1',
      type: 1,
      name: 'GitHub',
      username: 'octocat@example.com',
      password: 'gh_9f4Kd2!mQx7#Lp',
      totp: '',
      uri: 'https://github.com',
      notes: '个人主账号，已开启双因子登录。',
      favorite: true,
      folderId: 'f-1',
      revisionDate: '2026-11-10T08:12:00.000000Z',
      broken: false
    },
    {
      id: 'demo-2',
      type: 1,
      name: '公司 VPN',
      username: 'zhang.wei',
      password: 'Vpn@2026#Corp',
      totp: 'JBSWY3DPEHPK3PXP',
      uri: 'vpn.example-corp.com',
      notes: '连接前先确认 TOTP 验证码。',
      favorite: true,
      folderId: 'f-2',
      revisionDate: '2026-11-12T02:30:00.000000Z',
      broken: false
    },
    {
      id: 'demo-3',
      type: 1,
      name: '阿里云控制台',
      username: '13800000000',
      password: 'Aliyun+2026/Secure',
      totp: '',
      uri: 'https://account.aliyun.com',
      notes: '含 + / = 等特殊字符，用来验证加解密与表单编码。',
      favorite: false,
      folderId: 'f-2',
      revisionDate: '2026-11-08T11:00:00.000000Z',
      broken: false
    },
    {
      id: 'demo-4',
      type: 1,
      name: 'Notion',
      username: 'zhangwei@example.com',
      password: 'N0tion-Docs-2026',
      totp: '',
      uri: 'https://www.notion.so',
      notes: '',
      favorite: false,
      folderId: 'f-1',
      revisionDate: '2026-10-30T09:20:00.000000Z',
      broken: false
    },
    {
      id: 'demo-5',
      type: 3,
      name: '招商银行储蓄卡',
      username: '张三',
      password: '6225 8800 1234 5678',
      totp: '',
      uri: '',
      notes: '有效期 09/29，CVV 已脱敏。',
      favorite: false,
      folderId: 'f-3',
      revisionDate: '2026-09-18T14:00:00.000000Z',
      broken: false
    },
    {
      id: 'demo-6',
      type: 2,
      name: '服务器恢复码',
      username: '',
      password: '',
      totp: '',
      uri: '',
      notes: 'NAS 与路由器的恢复码集中记录在此条目。',
      favorite: false,
      folderId: 'f-2',
      revisionDate: '2026-11-01T07:45:00.000000Z',
      broken: false
    },
    {
      id: 'demo-7',
      type: 1,
      name: '旧版测试环境',
      username: 'legacy-bot',
      password: 'deprecated',
      totp: '',
      uri: 'http://10.0.0.12:8080',
      notes: '这条用于展示「无法解密」状态。',
      favorite: false,
      folderId: '',
      revisionDate: '2026-08-01T00:00:00.000000Z',
      broken: true
    }
  ];
  return items;
}

export function demoFolders(): VaultFolder[] {
  const folders: VaultFolder[] = [
    { id: 'f-1', name: '个人' },
    { id: 'f-2', name: '工作' },
    { id: 'f-3', name: '财务' }
  ];
  return folders;
}
