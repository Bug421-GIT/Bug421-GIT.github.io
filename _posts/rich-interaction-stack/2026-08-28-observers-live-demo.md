---
title: "IntersectionObserver、ResizeObserver、MutationObserver 的实时触发演示"
author: Ana-Ana
date: 2026-08-28
tags: [richInteraction]
categories: ["rich-interaction", "interaction-animation"]
section_order: 2
render_with_liquid: true
layout: post
pin: false
---

<h2 class="sr-only">IntersectionObserver、ResizeObserver、MutationObserver 的实时触发演示</h2>
<style>
.ob-wrap{display:grid;grid-template-columns:minmax(0,1fr) 230px;gap:16px;align-items:start}
.ob-viewport{height:280px;overflow:auto;border:0.5px solid var(--color-border-secondary);border-radius:var(--border-radius-lg);background:var(--color-background-secondary)}
.ob-target{width:120px;height:120px;margin:220px auto 0;background:var(--color-background-info);color:var(--color-text-info);border-radius:var(--border-radius-md);display:flex;align-items:center;justify-content:center;flex-wrap:wrap;gap:4px;padding:8px;font-size:12px}
.ob-target span{background:var(--color-background-primary);border-radius:4px;padding:0 5px}
.ob-ctrl{display:flex;flex-direction:column;gap:10px}
.ob-logs{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-top:16px}
.ob-log{background:var(--color-background-secondary);border-radius:var(--border-radius-md);padding:10px 12px;font-size:12px;line-height:1.7;height:132px;overflow:auto}
.ob-log div{border-bottom:0.5px solid var(--color-border-tertiary)}
.ob-hint{font-size:12px;color:var(--color-text-tertiary);line-height:1.6}
</style>
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-bottom:16px">
<div style="background:var(--color-background-secondary);border-radius:var(--border-radius-md);padding:1rem"><div style="font-size:13px;color:var(--color-text-secondary)">IntersectionObserver 触发</div><div id="ioCount" style="font-size:24px;font-weight:500">0</div></div>
<div style="background:var(--color-background-secondary);border-radius:var(--border-radius-md);padding:1rem"><div style="font-size:13px;color:var(--color-text-secondary)">ResizeObserver 触发</div><div id="roCount" style="font-size:24px;font-weight:500">0</div></div>
<div style="background:var(--color-background-secondary);border-radius:var(--border-radius-md);padding:1rem"><div style="font-size:13px;color:var(--color-text-secondary)">MutationObserver 触发</div><div id="moCount" style="font-size:24px;font-weight:500">0</div></div>
</div>
<div class="ob-wrap">
<div class="ob-viewport" id="obViewport"><div class="ob-target" id="obTarget" data-flag="a">target<span>1</span></div></div>
<div class="ob-ctrl">
<div style="font-size:13px;color:var(--color-text-secondary)">尺寸 <span id="obSizeVal" style="color:var(--color-text-primary)">120px</span></div>
<input id="obSize" type="range" min="40" max="200" value="120" style="width:100%">
<button id="obAdd">添加子节点</button>
<button id="obRemove">删除子节点</button>
<button id="obAttr">切换 data-flag 属性</button>
<div class="ob-hint">滚动下方观察窗口让 target 进出视野 → 触发 IO；拖动滑块 → 触发 RO；点击按钮 → 触发 MO。三列日志互不干扰。</div>
</div>
</div>
<div class="ob-logs">
<div class="ob-log" id="ioLog" style="color:var(--color-text-info)"></div>
<div class="ob-log" id="roLog" style="color:var(--color-text-success)"></div>
<div class="ob-log" id="moLog" style="color:var(--color-text-warning)"></div>
</div>
<script>
(function(){
var target=document.getElementById('obTarget');
var vp=document.getElementById('obViewport');
var counts={io:0,ro:0,mo:0};
function log(k,msg){counts[k]++;document.getElementById(k+'Count').textContent=counts[k];var box=document.getElementById(k+'Log');var d=document.createElement('div');d.textContent=msg;box.prepend(d);while(box.children.length>6){box.lastChild.remove();}}
var io=new IntersectionObserver(function(es){for(var i=0;i<es.length;i++){var e=es[i];log('io','isIntersecting='+e.isIntersecting+' ratio='+Math.round(e.intersectionRatio*100)/100);}},{root:vp,threshold:[0,0.25,0.5,0.75,1]});
io.observe(target);
var ro=new ResizeObserver(function(es){for(var i=0;i<es.length;i++){var cr=es[i].contentRect;log('ro','contentBox w='+Math.round(cr.width)+' h='+Math.round(cr.height));}});
ro.observe(target);
var mo=new MutationObserver(function(ms){for(var i=0;i<ms.length;i++){var m=ms[i];var t=m.type;if(m.attributeName){t+=' '+m.attributeName;}if(m.addedNodes.length){t+=' +'+m.addedNodes.length+'node';}if(m.removedNodes.length){t+=' -'+m.removedNodes.length+'node';}log('mo',t);}});
mo.observe(target,{childList:true,attributes:true,subtree:true,attributeOldValue:true});
document.getElementById('obSize').addEventListener('input',function(e){var v=e.target.value;target.style.width=v+'px';target.style.height=v+'px';document.getElementById('obSizeVal').textContent=v+'px';});
document.getElementById('obAdd').addEventListener('click',function(){var s=document.createElement('span');s.textContent=Math.floor(Math.random()*99);target.appendChild(s);});
document.getElementById('obRemove').addEventListener('click',function(){var c=target.lastElementChild;if(c&&c.tagName==='SPAN'){c.remove();}});
document.getElementById('obAttr').addEventListener('click',function(){target.dataset.flag=target.dataset.flag==='a'?'b':'a';});
})();
</script>

<hr>

<h2>用 iframe 嵌入的独立演示页</h2>
<p>下面这个 demo 是一个<strong>完全独立的 HTML 页面</strong>（<code>assets/demo/demo-interaction.html</code>），通过 <code>&lt;iframe&gt;</code> 嵌入本文。它的样式与脚本都封闭在自己的文档里，与博客主题<strong>互不污染</strong>——你可以拖动小球、点按钮看过渡动画、试计数器。</p>
<iframe
  src="/assets/demo/demo-interaction.html"
  style="width:100%;height:440px;border:1px solid var(--color-border-secondary);border-radius:var(--border-radius-lg)"
  loading="lazy"
  title="独立演示页 demo"></iframe>
<p class="ob-hint">iframe 高度这里写死为 440px；若 demo 内容动态变化，可在 demo 页用 <code>ResizeObserver</code> + <code>postMessage</code> 向父页上报高度实现自适应（或改用无界 wujie 让 DOM 直接进主文档流）。</p>