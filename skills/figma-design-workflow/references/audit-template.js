// 画面の決まりの点検の雛形（読むだけ）
// 使い方は同じ所の audit.md。Figma の MCP の use_figma の code にこのファイルの中身を渡す（Figma の外では動かない）。
// 書き込みは一切しない。1回の呼び出しで、対象の画面を全部回る。
// 利用者が差し替えるのは「設定」の節だけ。値は全部「例」で、自分の傘の決まりに置き換える。
// 決まりの正（どの文書のどの節か）は、利用者の記録に書く。ここには写さない。
async function main() {
// ---------------------------------------------------------------- 設定（ここだけ差し替える）
const PAGE_ID = 'REPLACE_WITH_PAGE_NODE_ID'; // 点検する作業のページのノード id
const SCREEN_PREFIX = 'Screen'; // 例: 点検の対象は、この名前で始まる最上位の枠だけ
const SAMPLES = 2; // 決まりごと・画面ごとに返す代表のノードの数
const KINDS = 3; // 決まりごと・画面ごとに返す内訳（値の種類）の数
// 1つの決まりだけを詳しく見る時は、決まりの名前（例: 'overflow'）か名前の配列を入れる。返り値の上限に注意。ふだんは null
const DETAIL = null;
const isDetail = (r) => (Array.isArray(DETAIL) ? DETAIL.includes(r) : r === DETAIL);
const DETAIL_MAX = Array.isArray(DETAIL) && DETAIL.length > 1 ? 10 : 15;

// 点検しない部分木（実装に関係しない外枠の飾りなど）。部品の名前
const SKIP_COMPONENTS = ['Browser frame', 'Logo']; // 例

// カードとみなす部品の名前（カードの中だけを見る決まりの範囲）
const CARD_COMPONENTS = ['Card', 'Small card']; // 例
// カードの題とみなす字の大きさ（代表の表示に使うだけ）
const CARD_TITLE_SIZE = 20; // 例

// 字の段: 字体 → 大きさ → 使ってよい太さ
const TYPE_SCALE = { // 例（字体名・段は自分の決まりに置き換える）
  'Example Sans': { 24: ['Bold'], 16: ['Bold', 'Regular'], 14: ['Bold', 'Regular'], 12: ['Regular'] },
  'Example Numeric': { 48: ['Medium'], 32: ['Medium'], 16: ['Medium'] },
};
// 字の段の例外（字の層の名前と親の名前。決まりの例外として残すと決めた物だけ）
const TYPE_OK_NAME_RE = null; // 例: /^=$/
const TYPE_OK_PARENT_RE = null; // 例: /^Formula$/

// 大きい数字の決まり
const NUMBER_FAMILY = 'Example Numeric'; // 数字用の字体
const NUMBER_MIN_SIZE = 32; // この大きさ以上を「大きい数字」として段を見る
const NUMBER_STEPS = [48, 32, 16]; // 例: 大きい数字の段
const NUMBER_TOP_STEP = 48; // 最上段の数字だけは色も見る
const NUMBER_TOP_VAR = 'VariableID:REPLACE'; // 最上段の数字の色の変数 id（変数で見る。無ければ null）
const NUMBER_TOP_HEX = '#00aa66'; // 例: 変数を使わない時の色の値
const STATE_COLOR_HEX = []; // 状態の色（最上段の数字に使ってよい色）。例外と分かったら足す

// すき間・余白・角丸の段（実際に使われている値を数えて決める）
const SPACING_SCALE = [0, 4, 8, 12, 16, 24, 32]; // 例
const SPACING_EXCEPTIONS = [1]; // 例: 線の幅ぶん。場所と回数を決まりに書いた例外だけ
const SPACING_SNAP = [3, 5, 7]; // 実装で近い段へ寄せる値。Figma は直さず、違反に数えない
// これより大きい余白は、すき間でなく長さ（棒の位置・空きの埋め）に使っている物とみて数えない（数だけ返す）
const SPACING_LENGTH = 80; // 例
// 余白で位置を合わせている所（すき間でなく位置の指定）。層の名前と3つ上までの親の名前で見る。実装では余白でなく位置で書く
const POSITION_NAME_RE = /(?!)/; // 例: /Position wrapper|Pointer area/（何にも当たらない値を既定にしてある）
const RADIUS_SCALE = [0, 4, 8, 16, 999]; // 例
const RADIUS_BAR = 2; // 棒など細い物にだけ許す角丸（無ければ null）
const RADIUS_BAR_NAME_RE = /bar|band|cell/i; // 上の角丸を許す層の名前
const RADIUS_SNAP = [1, 6]; // 実装で寄せる値。違反に数えない
const BAR_NAME_RE = /bar/i; // 棒の中とみなす名前
const BAND_NAME_RE = /band/i; // 帯の中の余白は割合で決まる長さなので数だけ返す名前
const GRID_NAME_RE = /heatmap|grid/i; // マス目の中（角丸の例外）とみなす名前

// 灰色の地: 「カードの中に灰色の地を付けない」という決まりの例
const GRAY_MIN = 0.9; // 明るさがこれ以上（0〜1）の無彩色を淡い灰とみなす
const GRAY_MAX = 0.999; // これ未満（真っ白は灰に数えない）
const GRAY_MIN_SIDE = 4; // 短い辺がこれ以下の物は線なので地に数えない
const GRAY_SKIP = /badge|bar|band|cell|legend|divider/i; // 数えない部分木の名前（状態の札・棒・帯・凡例・区切りの線など）

// 枠線の箱: 決まりで枠を持つ部品（この部品・名前の部分木は数えない）
const BORDER_OK_NAMES = ['Button', 'Input', 'Table cell', 'Badge']; // 例（末尾が / の物は前方一致）
const BORDER_OK_RE = /^Table($|\|)|^Legend/; // 例: 名前がこれに当たる部分木も数えない
const BORDER_TYPES = ['FRAME', 'INSTANCE', 'RECTANGLE', 'COMPONENT'];

// 手組みの枠（部品でない枠）がカードの中にこの数以上あれば参考の数として返す
const HANDMADE_THRESHOLD = 10; // 例
// 参考の数は、違反の合計 totals に入れず reference に返す
const REFERENCE_RULES = ['handmade', 'halt'];

// はみ出し: これより小さいはみ出し（px）は数えない
const OVERFLOW_TOLERANCE = 1;
// はみ出し: 決まりで親の外へ出す物の名前（長い線・位置の枠・吹き出しの三角など）
const OVERFLOW_OK_NAMES = /^Reference line|^Pointer/; // 例

// 役割の違う変数への結び: 変数の名前の「/」の前（組）で見る。組の名前は自分の変数の命名に置き換える
const ROLE_TEXT_OK = /^(text|accent|badge|icon)\//; // 字の層に結んでよい組
const ROLE_GROUP_TEXT = 'text'; // 字でない層に結んではいけない組
const ROLE_GROUP_BORDER = 'border'; // 地（塗り）に結んではいけない組（線・極細の層は可）
const ROLE_GROUP_ICON = 'icon'; // アイコンでない層に結んではいけない組
const ROLE_GROUP_BG = 'background'; // 線に結んではいけない組
const ROLE_VECTOR_TYPES = ['VECTOR', 'BOOLEAN_OPERATION', 'STAR', 'POLYGON', 'LINE', 'ELLIPSE'];
const ROLE_ICON_RE = /icon|chevron|arrow/i; // アイコンとみなす層の名前（4つ上の親まで見る）

// アイコンの置き場の型（置く場所と大きさ）。使わないなら ICON_COMPONENT を null にする
const ICON_COMPONENT = 'Item icon'; // 例: アイコンの部品の名前
const TABLE_ROW_RE = /^Row\||Table row$/; // 例: 表の行とみなす層の名前
const ICON_ROW_SIZE = 24; // 例: 表の行の頭に置く大きさ
const ICON_WRAPPER_NAME = 'Icon slot'; // 例: アイコンを包む枠の名前（無ければ空文字）
// アイコンと字の重なり: 見えているアイコンの枠と、同じカードの中の見えている字の描かれた範囲が、縦横ともこれより大きく重なれば数える
const ICON_OVERLAP_TOLERANCE = 1;

// 幕（後ろを暗くする層）: 見た目の不透明度（塗りの不透明度 × 層の不透明度）が 1 未満でなければ数える。無ければ null
const SCRIM_NAME_RE = /^Scrim$/;

// 半透明の塗り・線の、決まった数。内訳がこれより減ったら translucentDrop に数える（totals に入る）。
// 変数への結び直しや変数の値の書き換えで、塗りの不透明度が 1 に戻ることがある。画面を変えて半透明を足した・消した時は、ここも直す。
// 数は必ず「書く前」に点検して取り、ここに写す（後の数どうしで比べると、戻った所を見逃す）。
const TRANSLUCENT_EXPECTED = { // 例（内訳の形は 'fill #rrggbb 不透明度' か 'stroke #rrggbb 不透明度'）
  'fill #000000 0.5': 1,
};

// 決まりごとの例外（ノード id）。「決まりの例外として残す」と決めた物をここに足す。理由はコメントに書く
const EXCEPTIONS = {
  gray: [], border: [], type: [], lineHeight: [], number: [], unbound: [], role: [], spacing: [], radius: [],
  handmade: [], overflow: [], halt: [], iconRowHead: [], iconOverlap: [], scrim: [],
};

// ---------------------------------------------------------------- 道具
const RULES = Object.keys(EXCEPTIONS);
const hex = (c) => '#' + [c.r, c.g, c.b].map((v) => Math.round(v * 255).toString(16).padStart(2, '0')).join('');
const isGray = (c) => {
  const mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b);
  return mx - mn <= 0.01 && mx >= GRAY_MIN && mx < GRAY_MAX; // 無彩色の淡い灰だけ
};
const nameHit = (name, list) => list.some((p) => (p.endsWith('/') ? name.startsWith(p) : name === p));
const inPosition = (n) => { let p = n; for (let i = 0; i < 4 && p; i++, p = p.parent) if (POSITION_NAME_RE.test(p.name)) return true; return false; };
const iconish = (n) => { let p = n; for (let i = 0; i < 4 && p; i++, p = p.parent) if (ROLE_ICON_RE.test(p.name)) return true; return false; };
const shown = (n, root) => { for (let p = n; p && p !== root; p = p.parent) if (p.visible === false) return false; return true; };
const compCache = new Map();
async function compName(n) {
  if (n.type !== 'INSTANCE') return null;
  if (compCache.has(n.id)) return compCache.get(n.id);
  const mc = await n.getMainComponentAsync();
  const k = mc ? (mc.parent && mc.parent.type === 'COMPONENT_SET' ? mc.parent.name : mc.name) : '?';
  compCache.set(n.id, k);
  return k;
}
function cardTitle(card) {
  const t = card.findOne((x) => x.type === 'TEXT' && x.visible && x.fontSize === CARD_TITLE_SIZE);
  return t ? t.characters.slice(0, 20) : card.name.slice(0, 20);
}
const varNames = {};
async function varName(id) {
  if (!(id in varNames)) { const v = await figma.variables.getVariableByIdAsync(id); varNames[id] = v ? v.name : ''; }
  return varNames[id];
}
const result = { screens: [], totals: {}, snapped: { spacing: 0, radius: 0 }, lengthPadding: 0, positionPadding: 0, bandPadding: 0, clippedOverflow: 0, translucent: { count: 0, kinds: {}, samples: [] } };
for (const r of RULES) result.totals[r] = 0;

function push(bucket, rule, node, card, detail) {
  if (EXCEPTIONS[rule].includes(node.id)) return;
  const b = bucket[rule];
  b.count += 1;
  const key = detail || '';
  b.kinds[key] = (b.kinds[key] || 0) + 1;
  const max = isDetail(rule) ? DETAIL_MAX : SAMPLES;
  if (b.samples.length < max && !b.samples.some((s) => s.detail === key)) {
    b.samples.push({ id: node.id, card: card ? cardTitle(card) : null, detail: isDetail(rule) ? `${key} [${node.name.slice(0, 24)} / parent ${node.parent ? node.parent.name.slice(0, 16) : ''}]` : key });
  }
}

// 役割の違う変数への結び（値が同じだからと、層の役割と違う組の変数に結んだ物）
async function checkRole(bucket, n, card, prop, f) {
  if (f.type !== 'SOLID' || f.visible === false || !(f.boundVariables && f.boundVariables.color)) return;
  const nm = await varName(f.boundVariables.color.id);
  const g = nm.split('/')[0];
  const isText = n.type === 'TEXT';
  let why = null;
  if (isText && !ROLE_TEXT_OK.test(nm)) why = 'text layer bound to a non-text variable';
  else if (!isText && g === ROLE_GROUP_TEXT) why = 'text variable on a non-text layer';
  else if (!isText && g === ROLE_GROUP_BORDER && prop === 'fills' && !(ROLE_VECTOR_TYPES.includes(n.type) || Math.min(n.width, n.height) <= 2)) why = 'border variable used as a fill';
  else if (!isText && g === ROLE_GROUP_ICON && !(ROLE_VECTOR_TYPES.includes(n.type) || iconish(n))) why = 'icon variable on a non-icon layer';
  else if (!isText && g === ROLE_GROUP_BG && prop === 'strokes') why = 'background variable used as a stroke';
  if (why) push(bucket, 'role', n, card, `${why} ${nm}`);
}

// 字のスタイルと行の高さが違う: 字体・大きさ・太さが同じスタイルがあり、その行の高さのどれとも合わない字を数える。
// スタイルが無い組み合わせは見ない
const lhKey = (lh) => (lh.unit === 'AUTO' ? 'AUTO' : `${Math.round(lh.value * 100) / 100}${lh.unit === 'PIXELS' ? 'px' : '%'}`);
const styleLineHeights = {};
for (const st of await figma.getLocalTextStylesAsync()) {
  const k = `${st.fontName.family}|${st.fontSize}|${st.fontName.style}`;
  (styleLineHeights[k] = styleLineHeights[k] || new Set()).add(lhKey(st.lineHeight));
}

// ---------------------------------------------------------------- 本体
const page = await figma.getNodeByIdAsync(PAGE_ID);
await figma.setCurrentPageAsync(page);
const screens = page.children.filter((n) => n.type === 'FRAME' && n.name.startsWith(SCREEN_PREFIX));

// アイコンと字の重なり: カードごとの見えている字（root の内側で、どの祖先も隠れていない物）
const cardTexts = new Map();

for (const screen of screens) {
  const bucket = {};
  for (const r of RULES) bucket[r] = { count: 0, kinds: {}, samples: [] };

  // ctx: card = いまのカード, inInstance = カードより内側のインスタンスの中か, grayOff / borderOff = 数えない部分木
  async function walk(n, ctx) {
    if (n.visible === false) return;
    const cn = await compName(n);
    if (cn && SKIP_COMPONENTS.includes(cn)) return;

    const c = { ...ctx };
    if (cn && CARD_COMPONENTS.includes(cn)) { c.card = n; c.inInstance = false; c.cardRef = { n, handmade: 0 }; c.grayOff = false; c.borderOff = false; }
    else if (n.type === 'INSTANCE' && c.card) c.inInstance = true;
    const label = cn || n.name;
    if (c.card && GRAY_SKIP.test(label)) c.grayOff = true;
    if (BAR_NAME_RE.test(label)) c.inBar = true;
    if (c.card && (nameHit(label, BORDER_OK_NAMES) || BORDER_OK_RE.test(label))) c.borderOff = true;
    if (BAND_NAME_RE.test(label)) c.inBand = true;
    if (GRID_NAME_RE.test(label)) c.inGrid = true;

    // 幕
    if (SCRIM_NAME_RE && SCRIM_NAME_RE.test(n.name)) {
      let paint = 0;
      for (const f of Array.isArray(n.fills) ? n.fills : []) {
        if (f.visible === false) continue;
        // 透明度を持つ変数に結んだ塗りは、変数の透明度が塗りの opacity に写る（使う環境で一度確かめる）ので、opacity だけ見ればよい
        paint = Math.max(paint, f.opacity === undefined ? 1 : f.opacity);
      }
      const eff = paint * n.opacity; // 判定は丸める前の値で
      if (eff >= 1) push(bucket, 'scrim', n, c.card, `effective opacity ${Math.round(eff * 1000) / 1000}`);
    }

    // 灰色の地
    if (c.card && !c.grayOff && n !== c.card && n.type !== 'TEXT' && Array.isArray(n.fills) && Math.min(n.width, n.height) > GRAY_MIN_SIDE) {
      for (const f of n.fills) {
        if (f.type === 'SOLID' && f.visible !== false && (f.opacity === undefined || f.opacity > 0) && isGray(f.color)) push(bucket, 'gray', n, c.card, hex(f.color));
      }
    }

    // 枠線の箱（4辺を囲む線だけ。片側・2辺の線は罫線として数えない。カードそのものの層と、その直下も数えない）
    if (c.card && !c.borderOff && n !== c.card && n.parent !== c.card && BORDER_TYPES.includes(n.type)
      && Array.isArray(n.strokes) && n.strokes.some((s) => s.visible !== false)
      && Math.min(n.width, n.height) > 2) {
      const sides = n.strokeWeight === figma.mixed
        ? [n.strokeTopWeight, n.strokeRightWeight, n.strokeBottomWeight, n.strokeLeftWeight].filter((w) => w > 0).length
        : (n.strokeWeight > 0 ? 4 : 0);
      if (sides === 4) push(bucket, 'border', n, c.card, `${n.type} stroke ${n.strokeWeight === figma.mixed ? 'mixed' : n.strokeWeight}`);
    }

    // 字の段・数字
    if (n.type === 'TEXT') {
      const segs = n.getStyledTextSegments(['fontName', 'fontSize', 'fills', 'lineHeight', 'openTypeFeatures', 'textStyleId']);
      for (const s of segs) {
        const fam = s.fontName.family, st = s.fontName.style, sz = s.fontSize;
        const ok = TYPE_SCALE[fam] && TYPE_SCALE[fam][sz] && TYPE_SCALE[fam][sz].includes(st);
        const excused = TYPE_OK_NAME_RE && TYPE_OK_NAME_RE.test(n.name) && (!TYPE_OK_PARENT_RE || (n.parent && TYPE_OK_PARENT_RE.test(n.parent.name)));
        if (!ok && !excused) push(bucket, 'type', n, c.card, `${fam} ${sz} ${st}`);
        // HALT（括弧などを半分の幅で組む指定）は、指定の無いスタイルに結ぶと消えて幅が変わる。結んではいけない字として数だけ返し、行の高さは見ない
        const halt = s.openTypeFeatures && s.openTypeFeatures.HALT;
        if (halt) push(bucket, 'halt', n, c.card, `${fam} ${sz} ${st}${s.textStyleId ? '' : ' (no style)'}`);
        const lhs = styleLineHeights[`${fam}|${sz}|${st}`];
        if (!halt && lhs && !lhs.has(lhKey(s.lineHeight))) push(bucket, 'lineHeight', n, c.card, `${fam} ${sz} ${st} line height ${lhKey(s.lineHeight)} (style: ${[...lhs].join(' / ')})`);
        if (fam === NUMBER_FAMILY && sz >= NUMBER_MIN_SIZE) {
          if (!NUMBER_STEPS.includes(sz)) push(bucket, 'number', n, c.card, `size ${sz}`);
          else if (sz === NUMBER_TOP_STEP) {
            const f = (s.fills || []).find((x) => x.type === 'SOLID' && x.visible !== false);
            if (f) {
              const v = f.boundVariables && f.boundVariables.color && f.boundVariables.color.id;
              const h = hex(f.color);
              if (v !== NUMBER_TOP_VAR && h !== NUMBER_TOP_HEX && !STATE_COLOR_HEX.includes(h)) push(bucket, 'number', n, c.card, `color of ${NUMBER_TOP_STEP}: ${h}`);
            }
          }
        }
        // 色の結び（字の色）
        for (const f of s.fills || []) {
          if (f.type === 'SOLID' && f.visible !== false && !(f.boundVariables && f.boundVariables.color)) push(bucket, 'unbound', n, c.card, `text ${hex(f.color)}`);
          await checkRole(bucket, n, c.card, 'fills', f);
        }
      }
    } else {
      // 色の結び（塗り・線）
      for (const [kind, arr] of [['fill', n.fills], ['stroke', n.strokes]]) {
        if (!Array.isArray(arr)) continue;
        for (const f of arr) {
          if (f.type === 'SOLID' && f.visible !== false && !(f.boundVariables && f.boundVariables.color)) push(bucket, 'unbound', n, c.card, `${kind} ${hex(f.color)}`);
          await checkRole(bucket, n, c.card, kind === 'fill' ? 'fills' : 'strokes', f);
          // 半透明の塗り・線（数と内訳）。透明度を持たない変数に結ぶと・その値を書き換えると opacity が 1 に戻るので、決まった数と比べる
          if (f.type === 'SOLID' && f.visible !== false && f.opacity !== undefined && f.opacity < 1) {
            const k = `${kind} ${hex(f.color)} ${Math.round(f.opacity * 100) / 100}`;
            result.translucent.count += 1;
            result.translucent.kinds[k] = (result.translucent.kinds[k] || 0) + 1;
            if (result.translucent.samples.length < SAMPLES * 4) result.translucent.samples.push(`${n.id} ${k}`);
          }
        }
      }
    }

    // すき間・余白（自動レイアウトの枠だけ）
    if ('layoutMode' in n && n.layoutMode && n.layoutMode !== 'NONE') {
      const vals = [];
      if (n.primaryAxisAlignItems !== 'SPACE_BETWEEN' && n.children.length > 1) vals.push(['gap', n.itemSpacing]);
      if (n.layoutWrap === 'WRAP' && n.counterAxisSpacing != null) vals.push(['gap', n.counterAxisSpacing]);
      for (const k of ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft']) vals.push(['padding', n[k]]);
      for (const [k, v] of vals) {
        if (typeof v !== 'number') continue;
        const r = Math.round(v * 100) / 100;
        if (SPACING_SCALE.includes(r) || SPACING_EXCEPTIONS.includes(r)) continue;
        if (SPACING_SNAP.includes(r)) { result.snapped.spacing += 1; continue; }
        if (Math.abs(r) > SPACING_LENGTH) { result.lengthPadding += 1; continue; }
        if (c.inBand) { result.bandPadding += 1; continue; }
        if (k === 'padding' && inPosition(n)) { result.positionPadding += 1; continue; }
        push(bucket, 'spacing', n, c.card, `${k} ${r}${c.inInstance || n.type === 'INSTANCE' ? ' (inside a component)' : ''}`);
      }
    }

    // 角丸
    if ('cornerRadius' in n && n.type !== 'TEXT') {
      const radii = n.cornerRadius === figma.mixed
        ? [n.topLeftRadius, n.topRightRadius, n.bottomRightRadius, n.bottomLeftRadius]
        : [n.cornerRadius];
      const hasLook = (Array.isArray(n.fills) && n.fills.some((f) => f.visible !== false))
        || (Array.isArray(n.strokes) && n.strokes.some((s) => s.visible !== false)) || n.clipsContent;
      for (const v of new Set(radii)) {
        if (!v || !hasLook) continue;
        const r = v >= 100 ? 999 : Math.round(v * 100) / 100;
        if (RADIUS_SCALE.includes(r)) continue;
        if (RADIUS_BAR !== null && r === RADIUS_BAR && (c.inBar || c.inBand || c.inGrid || RADIUS_BAR_NAME_RE.test(n.name) || RADIUS_BAR_NAME_RE.test(n.parent ? n.parent.name : ''))) continue;
        if (RADIUS_SNAP.includes(r)) { result.snapped.radius += 1; continue; }
        push(bucket, 'radius', n, c.card, `radius ${r}`);
      }
    }

    // 部品の外（カードの中の、ほかの部品に入っていない手組みの枠）
    if (c.cardRef && n !== c.card && !c.inInstance && (n.type === 'FRAME' || n.type === 'GROUP')) c.cardRef.handmade += 1;

    // 表の行の頭のアイコン（行の名前の字の左に、決めた大きさで置く）
    if (ICON_COMPONENT && cn === ICON_COMPONENT) {
      let row = null;
      for (let p = n.parent, i = 0; i < 4 && p && !row; i++, p = p.parent) if (TABLE_ROW_RE.test(p.name)) row = p;
      if (row) {
        const w = ICON_WRAPPER_NAME && n.parent && n.parent.name === ICON_WRAPPER_NAME ? n.parent : n;
        const box = w.parent;
        const sibs = box && 'children' in box ? box.children.filter((x) => x.visible !== false) : [];
        const next = sibs[sibs.indexOf(w) + 1];
        const head = box && box.layoutMode === 'HORIZONTAL' && w.layoutPositioning !== 'ABSOLUTE' && next && next.type === 'TEXT';
        if (!head) push(bucket, 'iconRowHead', n, c.card, `not left of the row label (${row.name.slice(0, 16)})`);
        else if (Math.round(n.width) !== ICON_ROW_SIZE || Math.round(n.height) !== ICON_ROW_SIZE) push(bucket, 'iconRowHead', n, c.card, `size ${Math.round(n.width)}x${Math.round(n.height)}`);
      }
    }

    // アイコンと字の重なり
    if (ICON_COMPONENT && cn === ICON_COMPONENT && c.card && n.absoluteBoundingBox) {
      if (!cardTexts.has(c.card.id)) cardTexts.set(c.card.id, c.card.findAll((t) => t.type === 'TEXT' && shown(t, c.card)));
      const b = n.absoluteBoundingBox, t = ICON_OVERLAP_TOLERANCE;
      const hit = cardTexts.get(c.card.id).find((x) => {
        const r = x.absoluteRenderBounds;
        if (!r) return false;
        const w = Math.min(b.x + b.width, r.x + r.width) - Math.max(b.x, r.x);
        const h = Math.min(b.y + b.height, r.y + r.height) - Math.max(b.y, r.y);
        return w > t && h > t;
      });
      if (hit) push(bucket, 'iconOverlap', n, c.card, `overlaps text (${hit.characters.slice(0, 12)})`);
    }

    // はみ出し（子が親の枠の外へ出ている）
    if ('children' in n && n.absoluteBoundingBox && n.type !== 'GROUP' && n !== screen) {
      const p = n.absoluteBoundingBox;
      for (const ch of n.children) {
        if (ch.visible === false || !ch.absoluteBoundingBox) continue;
        if (ch.type === 'LINE' || ('layoutPositioning' in ch && ch.layoutPositioning === 'ABSOLUTE' && n.clipsContent)) continue;
        const b = ch.absoluteBoundingBox, t = OVERFLOW_TOLERANCE;
        const out = Math.max(p.x - b.x, p.y - b.y, (b.x + b.width) - (p.x + p.width), (b.y + b.height) - (p.y + p.height));
        if (out <= t) continue;
        if (OVERFLOW_OK_NAMES.test(ch.name) || OVERFLOW_OK_NAMES.test(n.name)) continue;
        if (n.clipsContent) { result.clippedOverflow += 1; continue; } // 親で切れて見えない物は数だけ返す
        push(bucket, 'overflow', ch, c.card, `${Math.round(out)}px`);
      }
    }

    if ('children' in n) for (const ch of n.children) await walk(ch, c);

    if (c.cardRef && n === c.card && c.cardRef.handmade >= HANDMADE_THRESHOLD) {
      push(bucket, 'handmade', n, n, `hand-built frames ${c.cardRef.handmade}`);
    }
  }

  await walk(screen, { card: null, inInstance: false });

  const out = { id: screen.id, name: screen.name, rules: {} };
  for (const r of RULES) {
    const b = bucket[r];
    result.totals[r] += b.count;
    if (b.count === 0) continue;
    if (DETAIL && !isDetail(r)) { out.rules[r] = b.count; continue; }
    const kinds = Object.entries(b.kinds).sort((a, z) => z[1] - a[1]).slice(0, isDetail(r) ? DETAIL_MAX : KINDS)
      .map(([k, v]) => `${k} x${v}`);
    out.rules[r] = { count: b.count, kinds, samples: b.samples.map((x) => `${x.id}${x.card ? ' ' + x.card : ''} ${x.detail}`) };
  }
  result.screens.push(out);
}

// 半透明の数が決まった数より減った所
result.translucent.drop = [];
result.totals.translucentDrop = 0;
for (const [k, want] of Object.entries(TRANSLUCENT_EXPECTED)) {
  const got = result.translucent.kinds[k] || 0;
  if (got < want) { result.translucent.drop.push(`${k} ${want}->${got}`); result.totals.translucentDrop += want - got; }
}

result.reference = {};
for (const r of REFERENCE_RULES) { result.reference[r] = result.totals[r]; delete result.totals[r]; }
return result;
}
return main();
