/**
 * 预置公司 Logo（真实品牌图形，SVG 来自 simple-icons，CC0 授权），放在
 * resources/rawfile/logos/*.svg，运行时按品牌色着色后显示在白色圆底上。
 *
 * 存储：写入条目的保留自定义字段（名字 `logo`，值以 `vwlogo:` 开头），
 * 加密后随条目同步，展示时会从自定义字段列表里过滤掉。
 */

export interface BrandLogo {
  key: string;
  label: string;
  /** rawfile 里的 svg 文件名（不含 .svg） */
  svg: string;
  /** 品牌色（用于给单色 SVG 着色） */
  color: string;
  /** 自动匹配关键字（小写） */
  aliases: string[];
}

export const LOGO_FIELD_NAME: string = 'logo';
export const LOGO_VALUE_PREFIX: string = 'vwlogo:';

export const BRAND_LOGOS: BrandLogo[] = [
  { key: 'google', label: 'Google', svg: 'google', color: '#4285F4', aliases: ['google', '谷歌', 'gmail'] },
  { key: 'microsoft', label: 'Microsoft', svg: 'microsoft', color: '#5E5E5E', aliases: ['microsoft', '微软', 'outlook', 'office'] },
  { key: 'apple', label: 'Apple', svg: 'apple', color: '#111111', aliases: ['apple', '苹果', 'icloud', 'appstore'] },
  { key: 'amazon', label: 'Amazon', svg: 'amazon', color: '#FF9900', aliases: ['amazon', '亚马逊', 'aws'] },
  { key: 'github', label: 'GitHub', svg: 'github', color: '#181717', aliases: ['github', 'git hub'] },
  { key: 'wechat', label: '微信', svg: 'wechat', color: '#07C160', aliases: ['微信', 'wechat', 'weixin'] },
  { key: 'alipay', label: '支付宝', svg: 'alipay', color: '#1677FF', aliases: ['支付宝', 'alipay', '蚂蚁'] },
  { key: 'taobao', label: '淘宝', svg: 'taobao', color: '#FF5000', aliases: ['淘宝', 'taobao', '天猫', 'tmall'] },
  { key: 'baidu', label: '百度', svg: 'baidu', color: '#2932E1', aliases: ['百度', 'baidu'] },
  { key: 'tencentqq', label: '腾讯 QQ', svg: 'tencentqq', color: '#12B7F5', aliases: ['腾讯', 'tencent', 'qq'] },
  { key: 'xiaomi', label: '小米', svg: 'xiaomi', color: '#FF6900', aliases: ['小米', 'xiaomi', 'mi.com'] },
  { key: 'huawei', label: '华为', svg: 'huawei', color: '#CF0A2C', aliases: ['华为', 'huawei', 'harmony'] },
  { key: 'samsung', label: '三星', svg: 'samsung', color: '#1428A0', aliases: ['三星', 'samsung'] },
  { key: 'alibabacloud', label: '阿里云', svg: 'alibabacloud', color: '#FF6A00', aliases: ['阿里云', 'aliyun', 'ali cloud'] },
  { key: 'notion', label: 'Notion', svg: 'notion', color: '#111111', aliases: ['notion'] },
  { key: 'x', label: 'X', svg: 'x', color: '#111111', aliases: ['twitter', '推特', 'x.com'] },
  { key: 'facebook', label: 'Facebook', svg: 'facebook', color: '#1877F2', aliases: ['facebook', '脸书', 'meta'] },
  { key: 'netflix', label: 'Netflix', svg: 'netflix', color: '#E50914', aliases: ['netflix', '奈飞'] },
  { key: 'tiktok', label: '抖音 TikTok', svg: 'tiktok', color: '#111111', aliases: ['抖音', 'douyin', 'tiktok'] },
  { key: 'gmail', label: 'Gmail', svg: 'gmail', color: '#EA4335', aliases: ['gmail', '谷歌邮箱'] },
  { key: 'googledrive', label: 'Google 云端硬盘', svg: 'googledrive', color: '#4285F4', aliases: ['drive', '云端硬盘'] },
  { key: 'icloud', label: 'iCloud', svg: 'icloud', color: '#3693F3', aliases: ['icloud', '云上贵州'] },
  { key: 'youtube', label: 'YouTube', svg: 'youtube', color: '#FF0000', aliases: ['youtube', '油管'] },
  { key: 'bilibili', label: '哔哩哔哩', svg: 'bilibili', color: '#00A1D6', aliases: ['bilibili', 'b站', '哔哩哔哩'] },
  { key: 'zhihu', label: '知乎', svg: 'zhihu', color: '#0084FF', aliases: ['知乎', 'zhihu'] },
  { key: 'netease', label: '网易云音乐', svg: 'neteasecloudmusic', color: '#C20C2C', aliases: ['网易', 'netease', '网易云'] }
];

export function brandOf(key: string): BrandLogo | null {
  for (let i = 0; i < BRAND_LOGOS.length; i++) {
    if (BRAND_LOGOS[i].key === key) {
      return BRAND_LOGOS[i];
    }
  }
  return null;
}

/** 根据条目名称猜品牌；匹配不到返回 '' */
export function matchBrand(name: string): string {
  const text: string = name.trim().toLowerCase();
  if (text.length === 0) {
    return '';
  }
  for (let i = 0; i < BRAND_LOGOS.length; i++) {
    const aliases: string[] = BRAND_LOGOS[i].aliases;
    for (let k = 0; k < aliases.length; k++) {
      if (text.indexOf(aliases[k]) >= 0) {
        return BRAND_LOGOS[i].key;
      }
    }
  }
  return '';
}


/** 按网址（域名）匹配内置品牌；匹配不到返回 '' */
export function matchBrandByUri(uri: string): string {
  let text: string = uri.trim().toLowerCase();
  if (text.length === 0) {
    return '';
  }
  const scheme: number = text.indexOf('://');
  if (scheme >= 0) {
    text = text.substring(scheme + 3);
  }
  const slash: number = text.indexOf('/');
  if (slash >= 0) {
    text = text.substring(0, slash);
  }
  const colon: number = text.indexOf(':');
  if (colon >= 0) {
    text = text.substring(0, colon);
  }
  if (text.startsWith('www.')) {
    text = text.substring(4);
  }
  if (text.length === 0) {
    return '';
  }
  for (let i = 0; i < BRAND_LOGOS.length; i++) {
    const key: string = BRAND_LOGOS[i].key.toLowerCase();
    if (text.indexOf(key) >= 0) {
      return BRAND_LOGOS[i].key;
    }
    const aliases: string[] = BRAND_LOGOS[i].aliases;
    for (let k = 0; k < aliases.length; k++) {
      const alias: string = aliases[k].toLowerCase();
      // 别名里可能有中文，域名只比 ASCII
      if (/^[a-z0-9.-]+$/.test(alias) && alias.length >= 3 && text.indexOf(alias) >= 0) {
        return BRAND_LOGOS[i].key;
      }
    }
  }
  return '';
}

export function logoPresetValue(key: string): string {
  return `${LOGO_VALUE_PREFIX}preset:${key}`;
}

/** 供 UI 直接用的 svg 路径 */
export function logoSvgPath(svg: string): string {
  return `logos/${svg}.svg`;
}

/** 名称的首字/首字母（英文取大写首字母，中文取第一个字） */
export function initialOf(name: string): string {
  const text: string = name.trim();
  if (text.length === 0) {
    return '';
  }
  const first: string = text.charAt(0);
  const upper: string = first.toUpperCase();
  return upper;
}

/** 由名称稳定生成一个颜色（同一名称每次一样） */
const INITIAL_COLORS: string[] = [
  '#4285F4', '#EA4335', '#34A853', '#FBBC05', '#7B61FF', '#00A1D6',
  '#FF6900', '#E1251B', '#07C160', '#1677FF', '#C20C2C', '#5E5E5E',
  '#0A59F7', '#8E44AD', '#16A085', '#D35400', '#2C3E50', '#C0392B'
];

export function colorForName(name: string): string {
  const text: string = name.trim();
  if (text.length === 0) {
    return '#0A59F7';
  }
  let hash: number = 0;
  for (let i = 0; i < text.length; i++) {
    hash = (hash * 31 + text.charCodeAt(i)) % 100000;
  }
  return INITIAL_COLORS[hash % INITIAL_COLORS.length];
}