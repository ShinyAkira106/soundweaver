// Renders docs/images/how-it-works.png: the "How it works" card strip for the README, in
// English, Chinese and Japanese at once. Laid out in HTML and captured with Playwright,
// because a README cannot carry its own styles. The menu bar, panel and HUD are drawn mocks
// and the numbers are examples.
//   npm install playwright   (once)
//   node scripts/how-it-works.js
"use strict";
const path = require("node:path");
const { chromium } = require("playwright");

const root = path.resolve(__dirname, "..");

// The menu bar glyph: a small waveform.
const WAVE = (size = 18, color = "currentColor") => {
  const bars = [[3, 4], [6, 9], [9, 15], [12, 19], [15, 12], [18, 7]];
  return `<svg viewBox="0 0 22 22" width="${size}" height="${size}">${bars
    .map(([x, h]) => `<rect x="${x - 0.9}" y="${11 - h / 2}" width="1.8" height="${h}" rx="0.9" fill="${color}"/>`)
    .join("")}</svg>`;
};
const SPEAKER = '<svg viewBox="0 0 22 22" width="14" height="14"><path d="M3.5 8.5h3.5l5-4v13l-5-4H3.5z" fill="currentColor"/></svg>';
const SPEAKER_LOUD = '<svg viewBox="0 0 22 22" width="16" height="16"><path d="M2.5 8.5h3l4.5-4v13l-4.5-4h-3z" fill="currentColor"/><path d="M13 8a4 4 0 0 1 0 6M15.5 5.5a7.5 7.5 0 0 1 0 11" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';
const WIFI = '<svg viewBox="0 0 22 22" width="16" height="16"><path d="M3 9a12 12 0 0 1 16 0M6 12a7.5 7.5 0 0 1 10 0M9 15a3 3 0 0 1 4 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
const BATTERY = '<svg viewBox="0 0 26 22" width="22" height="16"><rect x="1.5" y="6" width="20" height="10" rx="3" fill="none" stroke="currentColor" stroke-width="1.4"/><rect x="3.5" y="8" width="14" height="6" rx="1.5" fill="currentColor"/><rect x="22.5" y="9" width="2" height="4" rx="1" fill="currentColor"/></svg>';

const HTML = `<!doctype html><html><head><meta charset="utf-8"><style>
:root{--ink:#111315;--muted:#6e7378;--soft:#9aa0a6;--line:#ececec;--violet:#6b52e0;--violet-soft:rgba(107,82,224,.16);--coral:#ff8a6b;--sky:#6cbcff}
*{box-sizing:border-box}
html,body{margin:0;background:#fff}
body{width:1200px;padding:56px 64px 60px;font-family:Inter,"Noto Sans CJK SC",sans-serif;color:var(--ink);-webkit-font-smoothing:antialiased}
[lang=ja]{font-family:Inter,"Noto Sans CJK JP",sans-serif}
[lang=zh-CN]{font-family:Inter,"Noto Sans CJK SC",sans-serif}
h1{margin:0;font-size:42px;letter-spacing:-.02em;font-weight:700;line-height:1.1}
h1 small{font-size:22px;font-weight:600;color:var(--soft);letter-spacing:0;margin-left:14px}
.lead{margin:18px 0 0;max-width:900px;font-size:17px;line-height:1.55;color:#4a4f54}
.lead span{display:block;font-size:14.5px;color:var(--muted);line-height:1.6}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:44px}
.card{border:1px solid var(--line);border-radius:30px;overflow:hidden;display:flex;flex-direction:column;background:#fff}
.top{padding:24px 26px 20px;border-bottom:1px solid var(--line);height:262px}
.num{display:grid;place-items:center;width:26px;height:26px;border:1px solid #e3e3e3;border-radius:50%;font-size:12.5px;font-weight:600;color:#5b6065}
.title{margin:20px 0 0;font-size:22px;font-weight:700;letter-spacing:-.01em}
.alt{margin-top:4px;font-size:14px;font-weight:600;color:#3f4448}
.alt i{font-style:normal;color:var(--soft);font-weight:500;margin:0 6px}
.desc{margin-top:12px;font-size:14px;line-height:1.5;color:var(--muted)}
.desc span{display:block;font-size:12.5px;line-height:1.55;color:var(--soft)}
.art{position:relative;height:250px;background:linear-gradient(#fafafa,#f4f5f5);overflow:hidden}

/* the desktop behind the menu bar and the HUD */
.desk{position:absolute;left:26px;right:-30px;top:34px;bottom:-12px;border-radius:16px;overflow:hidden;
  background:radial-gradient(70% 90% at 75% 5%,#5a4bb0,transparent 70%),radial-gradient(60% 80% at 5% 95%,#a35a6e,transparent 70%),#1d1b33;
  box-shadow:0 18px 40px rgba(0,0,0,.18)}

/* 1: the menu bar with the new icon and its panel */
.menubar{position:absolute;left:0;right:0;top:0;height:30px;display:flex;align-items:center;gap:16px;padding:0 16px 0 18px;
  background:rgba(255,255,255,.14);color:rgba(255,255,255,.92);font-size:12px;font-weight:600}
.sw{position:relative;display:grid;place-items:center;color:#fff}
.sw::before{content:"";position:absolute;inset:-7px;border-radius:50%;border:2px solid rgba(160,140,255,.95);box-shadow:0 0 0 6px rgba(140,115,255,.25)}
.panel{position:absolute;left:12px;top:42px;width:212px;padding:9px;border-radius:16px;background:rgba(255,255,255,.86);
  box-shadow:0 10px 30px rgba(0,0,0,.25);display:flex;flex-direction:column;gap:7px}
.row{display:flex;align-items:center;gap:7px;height:26px;padding:0 8px;border-radius:9px;background:rgba(0,0,0,.06);font-size:11.5px;font-weight:600;color:#1f2124}
.row .grow{flex:1}
.toggle{width:28px;height:16px;border-radius:999px;background:#2f7cf6;position:relative}
.toggle::after{content:"";position:absolute;right:2px;top:2px;width:12px;height:12px;border-radius:50%;background:#fff}
.pill{position:relative;height:22px;margin:0 4px;border-radius:999px;background:rgba(0,0,0,.14);overflow:hidden;font-size:10.5px;font-weight:600;color:#5a5e63}
.pill b{position:absolute;left:0;top:0;bottom:0;border-radius:999px;background:#fff}
.pill span{position:absolute;left:9px;top:0;bottom:0;display:flex;align-items:center;gap:5px}

/* 2: one key press woven into two outputs */
.key{position:absolute;left:22px;width:66px;height:34px;display:flex;align-items:center;justify-content:center;gap:5px;border-radius:9px;
  background:#fff;border:1px solid #e3e3e3;border-bottom-width:3px;font-size:12px;font-weight:700;color:#3f4448}
.key small{font-weight:500;color:var(--soft);font-size:10.5px}
.lane{position:absolute;left:0;top:0}
.hub{position:absolute;left:142px;top:105px;width:40px;height:40px;border-radius:50%;display:grid;place-items:center;
  background:linear-gradient(135deg,#7a62ee,#3d338f);color:#fff;box-shadow:0 6px 16px rgba(80,60,200,.35)}
.out{position:absolute;right:16px;width:122px;padding:8px 10px;border-radius:12px;background:#fff;border:1px solid #e6e6e6;box-shadow:0 4px 10px rgba(0,0,0,.04)}
.out b{display:flex;align-items:center;gap:6px;font-size:12px;color:#2b2e31}
.out .dot{width:8px;height:8px;border-radius:50%}
.out small{display:block;margin-top:2px;font-size:10.5px;color:var(--soft)}
.out .lvl{margin-top:6px;height:5px;border-radius:999px;background:#eee;overflow:hidden}
.out .lvl i{display:block;height:100%;border-radius:999px}
.lane-label{position:absolute;left:112px;top:156px;width:100px;text-align:center;font-size:11px;line-height:1.5;color:var(--soft)}

/* 3: one HUD for both */
.stats{position:absolute;left:26px;top:30px;display:flex;gap:8px}
.chip{padding:8px 12px;border-radius:12px;background:#fff;border:1px solid #e6e6e6;font-size:12px;color:var(--muted);box-shadow:0 4px 10px rgba(0,0,0,.04)}
.chip b{display:block;font-size:17px;color:var(--violet);letter-spacing:-.01em}
.hud{position:absolute;left:22px;top:22px;width:262px;padding:10px 14px;border-radius:18px;color:#fff;
  background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.35);box-shadow:inset 0 1px 0 rgba(255,255,255,.35)}
.hud .name{font-size:11.5px;font-weight:700;text-shadow:0 1px 2px rgba(0,0,0,.35)}
.hud .line{display:flex;align-items:center;gap:8px;margin-top:8px}
.hud .track{position:relative;flex:1;height:4px;border-radius:999px;background:rgba(0,0,0,.25);box-shadow:inset 0 0 0 .7px rgba(255,255,255,.5)}
.hud .track b{position:absolute;left:0;top:0;bottom:0;border-radius:999px;background:#fff}
.hud .ticks{display:flex;justify-content:space-between;margin:5px 24px 0 22px}
.hud .ticks i{width:2px;height:2px;border-radius:50%;background:rgba(255,255,255,.7)}

.foot{margin-top:34px;display:flex;flex-direction:column;align-items:center;gap:22px}
.chips{display:flex;align-items:center;gap:8px;font-size:15px;color:var(--soft)}
.chips .tagpill{padding:8px 14px;border-radius:999px;background:#f2f2f2;color:var(--ink);font-weight:600;font-size:14px}
.chips .tagpill small{font-weight:500;color:var(--muted);margin-left:4px;font-size:12.5px}
.cta{display:flex;align-items:center;gap:10px;height:50px;padding:0 26px;border-radius:999px;background:#0e0f10;color:#fff;font-size:17px;font-weight:600}
.cta span{font-weight:500;color:#b9bdc1;font-size:14px}
</style></head><body>
<h1>How it works. <small lang="zh-CN">工作原理</small><small lang="ja">仕組み</small></h1>
<p class="lead">Install it once, then let it weave: every press of a volume key sets your monitor over DDC and your MacBook speakers together, each at its own share.
  <span lang="zh-CN">装好一次就不用管：每按一次音量键，显示器（通过 DDC）和 MacBook 扬声器都会一起变化，各自按设定的比例。</span>
  <span lang="ja">一度入れるだけ。音量キーを押すたびに、モニター（DDC 経由）と MacBook のスピーカーが、それぞれの割合で一緒に変わります。</span></p>

<div class="cards">
  <section class="card">
    <div class="top">
      <div class="num">1</div>
      <div class="title">Install once</div>
      <div class="alt"><span lang="zh-CN">装一次</span><i>·</i><span lang="ja">一度入れるだけ</span></div>
      <div class="desc">Drag it into Applications. A woven waveform joins the menu bar.
        <span lang="zh-CN">拖进“应用程序”，菜单栏会多一个声波图标。</span>
        <span lang="ja">アプリケーションへドラッグすると、メニューバーに波形アイコンが加わります。</span></div>
    </div>
    <div class="art">
      <div class="desk">
        <div class="menubar">
          <span class="sw">${WAVE(16)}</span>${WIFI}${BATTERY}<span>Sat 9:41</span>
        </div>
        <div class="panel">
          <div class="row">${WAVE(13, "#1f2124")}<span class="grow">Soundweaver</span><span class="toggle"></span></div>
          <div class="pill"><b style="width:56%"></b><span>${SPEAKER} 56%</span></div>
          <div class="row"><span class="grow">L27h-4A</span><span class="toggle"></span></div>
          <div class="pill"><b style="width:60%"></b><span>${SPEAKER} 60%</span></div>
        </div>
      </div>
    </div>
  </section>

  <section class="card">
    <div class="top">
      <div class="num">2</div>
      <div class="title">Just press the keys</div>
      <div class="alt"><span lang="zh-CN">照常按音量键</span><i>·</i><span lang="ja">いつも通りキーを押す</span></div>
      <div class="desc">One press, two outputs: the monitor over DDC, the MacBook via Core Audio.
        <span lang="zh-CN">一次按键两路输出：显示器走 DDC，MacBook 走系统音量。</span>
        <span lang="ja">1 回で 2 つの出力へ。モニターは DDC、MacBook はシステム音量。</span></div>
    </div>
    <div class="art">
      <svg class="lane" width="345" height="250" viewBox="0 0 345 250">
        <g fill="none" stroke-width="2" stroke-linecap="round">
          <path d="M88 52C125 52 120 118 146 122" stroke="#cfcbe0"/>
          <path d="M88 125H146" stroke="#cfcbe0"/>
          <path d="M88 198C125 198 120 132 146 128" stroke="#cfcbe0"/>
          <path d="M180 118C204 110 196 66 207 62" stroke="var(--coral)"/>
          <path d="M180 132C204 140 196 184 207 188" stroke="var(--sky)"/>
        </g>
      </svg>
      <div class="key" style="top:35px">F10 <small>mute</small></div>
      <div class="key" style="top:108px">F11 <small>−</small></div>
      <div class="key" style="top:181px">F12 <small>+</small></div>
      <div class="hub">${WAVE(20, "#fff")}</div>
      <div class="out" style="top:30px"><b><span class="dot" style="background:var(--coral)"></span>L27h-4A</b><small>DDC · VCP 0x62</small><div class="lvl"><i style="width:60%;background:var(--coral)"></i></div></div>
      <div class="out" style="top:156px"><b><span class="dot" style="background:var(--sky)"></span>MacBook</b><small>Core Audio</small><div class="lvl"><i style="width:100%;background:var(--sky)"></i></div></div>
    </div>
  </section>

  <section class="card">
    <div class="top">
      <div class="num">3</div>
      <div class="title">One HUD for both</div>
      <div class="alt"><span lang="zh-CN">一个提示框</span><i>·</i><span lang="ja">HUD はひとつ</span></div>
      <div class="desc">Set the balance once. The HUD shows the level and the outputs that are playing.
        <span lang="zh-CN">比例设一次就好，提示框显示音量和正在发声的设备。</span>
        <span lang="ja">割合は一度決めるだけ。HUD に音量と再生中の出力が表示されます。</span></div>
    </div>
    <div class="art">
      <div class="stats">
        <div class="chip"><b>56%</b>volume · 音量</div>
        <div class="chip"><b>2</b>outputs · 输出</div>
      </div>
      <div class="desk" style="top:118px">
        <div class="hud">
          <div class="name">L27h-4A + MacBook Pro Speakers</div>
          <div class="line">${SPEAKER}<div class="track"><b style="width:56%"></b></div>${SPEAKER_LOUD}</div>
          <div class="ticks">${"<i></i>".repeat(17)}</div>
        </div>
      </div>
    </div>
  </section>
</div>

<div class="foot">
  <div class="chips">Also works with
    <span class="tagpill">USB-C · DisplayPort</span>
    <span class="tagpill">Native HUD<small lang="zh-CN">系统提示框</small></span>
    <span class="tagpill">Launch at login<small lang="ja">自動起動</small><small lang="zh-CN">开机启动</small></span>
  </div>
  <div class="cta">Download <span lang="zh-CN">下载</span><span lang="ja">ダウンロード</span>
    <svg width="18" height="18" viewBox="0 0 18 18"><path d="M4 9h10M10 5l4 4-4 4" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
</div>
</body></html>`;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 2 });
  await page.setContent(HTML);
  await page.evaluate(() => document.fonts.ready);
  const output = path.join(root, "docs", "images", "how-it-works.png");
  await page.screenshot({ path: output, fullPage: true });
  await browser.close();
  console.log(output);
})();
