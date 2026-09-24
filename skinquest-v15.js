/* SkinQuest v15: customer deliveries, provider controls and owner analytics.
   No wallet or fulfilment changes are permitted through analytics calls. */
(() => {
  'use strict';
  const $ = (s,r=document) => r.querySelector(s);
  const $$ = (s,r=document) => [...r.querySelectorAll(s)];
  const safe = v => String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const n = v => Number(v||0).toLocaleString();
  const date = v => v ? new Date(v).toLocaleString([], {dateStyle:'medium',timeStyle:'short'}) : 'Not recorded';
  const names = {cpx:'CPX Research',timewall_surveys:'TimeWall Surveys',timewall_earn:'TimeWall Earn'};
  const terminal = s => ['completed','rejected','refunded','cancelled'].includes(s);
  const status = s => typeof formatStatus==='function' ? formatStatus(s) : s.replaceAll('_',' ');
  const badge = s => `<span class="status-pill status-${safe(s)}">${safe(status(s))}</span>`;
  const message = (t,k='info') => showMessage(t,k);
  const confirmAction = (text,options={}) => showConfirm(text,options);
  const urls = new Map(), tracking = new Map();
  let providerUser=null, providerRequest=0, bound=false, ordersSeq=0, adminSeq=0, earningsSeq=0;
  const customer={items:[],total:0,filter:'active'};
  let adminOrders=[];
  async function rpc(name,args={}) { const {data,error}=await sb.rpc(name,args); if(error)throw error;return data; }
  function errorBox(title,e) { return `<div class="sq15-empty"><strong>${safe(title)}</strong><p>${safe(e?.message||e||'Please try again.')}</p></div>`; }
  const lock = until => `<div class="sq15-lock"><span>Steam trade lock</span><strong data-sq146-countdown="${safe(until)}">${safe(formatTradeLockRemaining(until))}</strong><small>Unlocks ${date(until)} · delivery follows manual review</small></div>`;
  const toLocal = d => {const v=new Date(d);return new Date(v.getTime()-v.getTimezoneOffset()*60000).toISOString().slice(0,16);};
  function nextStep(o) {
    if(o.trade_url_needs_review&&!terminal(o.status)&&o.status!=='trade_sent')return 'Your updated trade link is awaiting staff review.';
    return ({pending:'Saved · waiting for review',reviewing:'Staff are reviewing your request',ordered:'Waiting for purchase and a confirmed unlock time',trade_locked:'Purchased · waiting for the Steam lock to end',ready_to_trade:'Ready · waiting for a manual Steam offer',trade_sent:'Offer marked sent · check your Steam offers',completed:'Delivery recorded as completed',refunded:'Closed · refund recorded in Coin history',rejected:'Request closed · check Coin history',cancelled:'Request cancelled · check Coin history'})[o.status]||'Check your order for details';
  }
  function group(items) {
    const map=new Map();for(const o of items){const k=o.delivery_id||`ungrouped:${o.user_id||'mine'}`;if(!map.has(k))map.set(k,[]);map.get(k).push(o);}return [...map.entries()];
  }
  async function record(source,kind) {
    if(!currentUser?.id)return;
    const key=`${currentUser.id}:${source}:${kind}`,now=Date.now();
    if(now-(tracking.get(key)||0)<5000)return;tracking.set(key,now);
    try{await rpc('sq_record_earning_activity',{p_source:source,p_kind:kind,p_launch_id:crypto.randomUUID()});}
    catch(e){console.warn('Earning engagement could not be recorded:',e.message);}
  }
  function resetProviders() {
    providerUser=null;urls.clear();
    $$('[data-cpx-direct]').forEach(b=>{b.removeAttribute('href');b.setAttribute('aria-disabled','true');});
    for(const source of ['timewall_surveys','timewall_earn']) {
      const frame=$(`[data-timewall-frame="${source}"]`);if(frame)frame.src='about:blank';
      $(`[data-timewall-stage="${source}"]`)?.classList.add('hidden');
      $$(`[data-provider-open="${source}"]`).forEach(b=>{b.removeAttribute('href');b.disabled=true;b.setAttribute('aria-disabled','true');});
    }
  }
  function safeTimewall(value,uid) {
    try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='timewall.io'&&
      u.searchParams.get('uid')===uid&&/^[a-zA-Z0-9_-]{8,100}$/.test(u.searchParams.get('oid')||'')?u.toString():null;}catch{return null;}
  }
  function configureProviders(data,uid) {
    if(currentUser?.id!==uid)return;
    if(providerUser!==uid){resetProviders();providerUser=uid;}
    const cpx=typeof isSafeOfferwallUrl==='function'&&isSafeOfferwallUrl(data?.wall_url,uid)?data.wall_url:null;
    if(cpx){urls.set('cpx',cpx);$$('[data-cpx-direct]').forEach(b=>{b.href=cpx;b.setAttribute('aria-disabled','false');});}
    else{urls.delete('cpx');$$('[data-cpx-direct]').forEach(b=>{b.removeAttribute('href');b.setAttribute('aria-disabled','true');});}
    for(const [source,key] of [['timewall_surveys','timewall_wall_url'],['timewall_earn','timewall_earn_url']]) {
      const url=safeTimewall(data?.[key],uid),panel=$(`[data-timewall-panel="${source}"]`);if(!panel)continue;
      if(url){urls.set(source,url);panel.classList.remove('hidden');
        $$(`[data-provider-open="${source}"]`).forEach(b=>{b.disabled=false;b.setAttribute('aria-disabled','false');if(b.tagName==='A')b.href=url;});
        $(`[data-timewall-empty="${source}"]`)?.classList.add('hidden');
        $(`[data-timewall-controls="${source}"]`)?.classList.remove('hidden');
        if(source==='timewall_surveys')$('#timewallProviderLink')?.classList.remove('hidden');
      }else{urls.delete(source);$$(`[data-provider-open="${source}"]`).forEach(b=>{b.removeAttribute('href');b.disabled=true;b.setAttribute('aria-disabled','true');});$(`[data-timewall-controls="${source}"]`)?.classList.add('hidden');
        const empty=$(`[data-timewall-empty="${source}"]`);empty?.classList.remove('hidden');
        if(empty&&source==='timewall_surveys')empty.innerHTML='<strong>TimeWall is unavailable right now</strong><p>Try CPX Research while we check the connection.</p>';}
    }
  }
  async function initProviders() {
    if(!$('[data-timewall-panel]'))return;
    const seq=++providerRequest,user=await getSessionUser();
    if(seq!==providerRequest)return;
    if(!user){resetProviders();$$('[data-timewall-empty]').forEach(e=>{e.classList.remove('hidden');e.innerHTML='<strong>Sign in to earn coins</strong><p>Your provider session is linked to your SkinQuest account.</p><button class="button button-primary" data-open-auth="login">Sign in</button>';});$$('[data-timewall-controls]').forEach(e=>e.classList.add('hidden'));return;}
    if(providerUser===user.id&&urls.size)return;
    try{const {data,error}=await sb.functions.invoke('survey-feed');if(error)throw error;
      if(seq===providerRequest&&currentUser?.id===user.id)configureProviders(data,user.id);
    }catch(e){if(seq!==providerRequest)return;$$('[data-timewall-empty]').forEach(el=>{el.classList.remove('hidden');el.innerHTML=errorBox('Provider connection unavailable',e)+'<button class="button button-ghost" data-provider-retry>Retry connection</button>';});}
  }
  function launchProvider(source,embed=false) {
    const url=urls.get(source);if(!url||providerUser!==currentUser?.id)return message('Sign in and reconnect your provider session.','error');
    record(source,'open');
    if(embed){const frame=$(`[data-timewall-frame="${source}"]`),stage=$(`[data-timewall-stage="${source}"]`);if(!frame||!stage)return;
      stage.classList.remove('hidden');frame.src=url;
      const label=$('[data-frame-status]',stage);if(label)label.textContent='Loading TimeWall…';
      frame.onload=()=>{if(frame.src!=='about:blank'&&providerUser===currentUser?.id){if(label)label.textContent='TimeWall frame loaded';record(source,'view');}};
    }
  }
  function orderRow(o) {
    return `<article class="sq15-order-row"><div><a class="sq15-order-title" href="/orders/${o.id}">${o.reward_id==null?'Deleted item · ':''}${safe(o.reward_name)}</a><small>${safe(o.order_number)} · ${n(o.points_coins||o.points_cost)} coins</small><p>${safe(nextStep(o))}</p>${o.status==='trade_locked'&&o.trade_locked_until?lock(o.trade_locked_until):''}</div><div class="sq15-order-state">${badge(o.status)}<a href="/orders/${o.id}" class="sq15-text-link">Order details →</a></div></article>`;
  }
  async function myOrders(append=false) {
    const root=$('#myOrders');if(!root)return;
    const seq=++ordersSeq,user=await getSessionUser();if(seq!==ordersSeq)return;
    if(!user){customer.items=[];root.innerHTML=errorBox('Your orders are private','Sign in with the account that placed your orders.')+'<button class="button button-primary" data-open-auth="login">Sign in</button>';return;}
    if(!append)root.innerHTML='<div class="sq15-empty">Loading your orders…</div>';
    try{const data=await rpc('sq_my_orders',{p_status:customer.filter,p_limit:50,p_offset:append?customer.items.length:0});
      if(seq!==ordersSeq||currentUser?.id!==user.id)return;
      customer.items=append?[...customer.items,...data.items]:data.items;customer.total=Number(data.total);
      const stats=$('#myOrderStats');if(stats)stats.innerHTML=[['Active orders',data.active],['Waiting on a lock',data.locked],['Trade marked sent',data.sent]].map(([label,value])=>`<div><strong>${n(value)}</strong><span>${label}</span></div>`).join('');
      root.innerHTML=group(customer.items).map(([key,items])=>`<section class="panel sq15-delivery">${key.startsWith('ungrouped:')?'':`<header><div><h2>Steam delivery</h2><p class="muted">${n(items.length)} item${items.length===1?'':'s'} · may arrive in the same Steam offer</p></div></header>`}${items.map(orderRow).join('')}</section>`).join('')||errorBox('No orders in this view','Choose a reward to start your first order.');
      if(customer.items.length<customer.total)root.insertAdjacentHTML('beforeend',`<button class="button button-ghost" data-orders-more>Load more orders (${n(customer.items.length)} / ${n(customer.total)})</button>`);
    }catch(e){if(seq===ordersSeq)root.innerHTML=errorBox('Could not load orders',e)+'<button class="button button-ghost" data-orders-retry>Try again</button>';}
  }
  function augmentOrder(item) {
    const root=$('#orderDetail');if(!root||!item)return;
    if(item.trade_url_needs_review)root.insertAdjacentHTML('afterbegin','<aside class="sq15-notice">Your trade link changed. Staff will review the new link before sending this order. An already-sent offer is not redirected.</aside>');
    if(item.delivery_id&&item.delivery_items?.length)root.insertAdjacentHTML('beforeend',`<section class="panel sq15-delivery"><h2>Items in this delivery</h2><p class="muted">These items may arrive in the same Steam offer.</p>${item.delivery_items.map(s=>`<a class="sq15-sibling" href="/orders/${s.id}"><span><strong>${safe(s.reward_name)}</strong><small>${safe(s.order_number)} · ${n(s.coins)} coins</small></span>${badge(s.status)}</a>`).join('')}</section>`);
  }
  function deliveryStep(items) {
    if(!items.length)return null;
    const statuses=new Set(items.map(o=>o.status)),modes=new Set(items.map(o=>o.fulfillment_mode));
    if(statuses.size===1&&statuses.has('trade_sent'))return {target:'completed',label:'Mark delivered',help:'Only after the customer has accepted the Steam offer.'};
    if(statuses.size===1&&statuses.has('ready_to_trade'))return {target:'trade_sent',label:'Mark Steam offer sent',help:'Send the offer in Steam first, then record it here.'};
    if(statuses.size===1&&statuses.has('trade_locked')) {
      return items.every(o=>o.trade_locked_until&&new Date(o.trade_locked_until)<=new Date())
        ? {target:'ready_to_trade',label:'Mark ready to trade',help:'Check Steam: the recorded lock has ended.'} : null;
    }
    if(modes.size===1&&modes.has('orderable')&&items.every(o=>['pending','reviewing','ordered'].includes(o.status)))
      return statuses.size===1&&statuses.has('ordered')
        ? {target:'trade_locked',label:'Mark purchased / trade locked',help:'Set the actual unlock time shown by Steam. Eight days is filled in as a starting estimate.'}
        : {target:'ordered',label:'Mark awaiting purchase',help:'Use after accepting these orders for fulfilment.'};
    if(modes.size===1&&modes.has('stocked')&&items.every(o=>['pending','reviewing','ordered'].includes(o.status)))
      return {target:'ready_to_trade',label:'Mark ready to trade',help:'Confirm these prepared items are available in the sending Steam account.'};
    return null;
  }
  function tradeMessage(items,id) {
    const numbers=items.map(o=>o.order_number).join(', ');
    const prefix=`SkinQuest ${items.length===1?'order':'orders'} ${numbers}`;
    const message=`${prefix} - ${items.length===1?items[0].reward_name:`${items.length} items`}`;
    if(message.length<=125)return message;
    if(prefix.length<=100)return `${prefix} - verify items.`;
    return `SkinQuest delivery ${String(id||items[0].id).slice(0,8)} - ${items.length} orders; verify items on SkinQuest.`;
  }
  function steamNote(items,id) {
    return `<div class="sq15-steam-copy"><label>Message to paste into Steam<textarea class="sq15-steam-note" rows="2" readonly>${safe(tradeMessage(items,id))}</textarea></label><button type="button" class="admin-secondary-button" data-copy-note>Copy Steam message</button></div>`;
  }
  function tradeAddress(item) {
    const url=item.steam_trade_url;
    return `<div class="sq15-trade-address"><span>Saved trade link</span><code>${safe(url||'Missing — ask the customer to add one')}</code>${url?'<button class="admin-secondary-button" type="button" data-copy-url>Copy trade link</button>':''}</div>`;
  }
  function actionForm(items,grouped,id,complete) {
    const step=deliveryStep(items);
    if(!complete)return '<p class="sq15-next-step">Load all orders in this delivery before applying a shared step.</p>';
    if(!step)return `<p class="sq15-next-step">${items.every(o=>o.status==='trade_locked')?'Wait for the recorded Steam locks to end. You can open an order to inspect its exact time.':'These items are at different steps. Open individual orders to bring them to the same step.'}</p>`;
    const stale=step.target==='trade_sent'&&items.some(o=>o.trade_url_needs_review);
    const missing=step.target==='trade_sent'&&items.some(o=>!o.steam_trade_url);
    return `<form class="sq15-guided-action" ${grouped?`data-delivery-update="${safe(id)}"`:`data-single-update="${items[0].id}"`} data-target="${step.target}"><div><span class="admin-eyebrow">Next step for ${items.length} order${items.length===1?'':'s'}</span><h3>${safe(step.label)}</h3><p>${safe(step.help)}</p></div>
      ${step.target==='trade_locked'?`<label>Steam tradable time<input name="until" type="datetime-local" value="${toLocal(Date.now()+192*3600000)}" required /><small>Check the exact time in Steam before saving.</small></label>`:''}
      ${step.target==='trade_sent'?`<label>Sent offer URL (optional)<input name="offer" maxlength="500" placeholder="https://steamcommunity.com/tradeoffer/123456789/" /></label>`:''}
      ${stale||missing?'<p class="sq15-next-step">Review the changed trade link and save a valid one before marking sent.</p>':''}
      <button class="admin-primary-button" type="submit" ${stale||missing?'disabled':''}>${safe(step.label)}</button></form>`;
  }
  function renderDeliveryCard(key,items) {
    const first=items[0],grouped=!!first.delivery_id;
    const canGroup=items.filter(o=>o.status!=='trade_sent');
    const complete=!grouped||items.length===Number(first.delivery_total||items.length);
    return `<section class="admin-card sq15-admin-delivery" data-delivery-group="${safe(key)}"><header><div><span class="admin-eyebrow">${grouped?'Shared Steam delivery':'Individual orders · one customer'}</span><h2>${safe(first.steam_name||first.username||first.user_id)}</h2><p>${safe(first.contact_email||'Contact email not recorded')} · ${items.length} order${items.length===1?'':'s'}</p>${grouped?`<small>Delivery #${safe(first.delivery_id.slice(0,8))} · All listed items travel together</small>`:''}</div>${!grouped&&canGroup.length>1?'<label class="sq15-check"><input type="checkbox" data-select-group />Select all unsent</label>':''}</header>
    ${grouped?`<div class="sq15-group-summary">${items.map(o=>`<div class="sq15-admin-order"><button class="sq15-order-open" type="button" data-open-fulfilment-order="${o.id}"><strong>${safe(o.reward_name)}</strong><small>${safe(o.order_number)} · ${n(o.points_coins||o.points_cost)} coins</small></button><div>${badge(o.status)}${o.status==='trade_locked'&&o.trade_locked_until?`<small>${safe(formatTradeLockRemaining(o.trade_locked_until))} · ${date(o.trade_locked_until)}</small>`:''}</div></div>`).join('')}</div>
      <div class="sq15-fulfil-controls">${tradeAddress(first)}${complete?steamNote(items,first.delivery_id):'<p class="sq15-next-step">Load every item in this delivery before copying the Steam message.</p>'}
      ${items.some(o=>o.trade_url_needs_review)?`<div class="sq15-notice"><strong>Customer changed their trade link</strong><p>Check the Steam account before sending any unsent item.</p><code>${safe(first.current_trade_url||'Missing trade link')}</code><button class="admin-secondary-button" type="button" data-review-delivery="${safe(first.delivery_id)}" data-expected-trade="${safe(first.current_trade_url||'')}" ${!first.current_trade_url?'disabled':''}>Review and use new link</button></div>`:''}
      ${actionForm(items,true,first.delivery_id,complete)}</div>`:
      `<div class="sq15-individual-list">${items.map(o=>`<div class="sq15-individual-order"><div class="sq15-individual-heading">${o.status!=='trade_sent'?`<label class="sq15-check"><input aria-label="Select ${safe(o.order_number)} for a shared delivery" type="checkbox" value="${o.id}" data-group-order /></label>`:''}<button class="sq15-order-open" type="button" data-open-fulfilment-order="${o.id}"><strong>${safe(o.reward_name)}</strong><small>${safe(o.order_number)} · ${n(o.points_coins||o.points_cost)} coins</small></button>${badge(o.status)}</div><div class="sq15-fulfil-controls">${tradeAddress(o)}${steamNote([o],null)}${o.trade_url_needs_review?'<p class="sq15-next-step">Customer changed the trade link. Open this order to review it before sending.</p>':''}${actionForm([o],false,null,true)}</div></div>`).join('')}</div>
      ${canGroup.length>1?'<div class="sq15-group-create"><button class="admin-secondary-button" type="button" data-create-delivery>Send selected orders together</button><small>Choose only orders intended for one Steam offer. The same customer is already selected.</small></div>':''}`}</section>`;
  }
  async function adminDeliveries(append=false) {
    const root=$('#adminDeliveries');if(!root)return;
    const seq=++adminSeq;if(!append)root.innerHTML='<div class="admin-empty">Loading deliveries…</div>';
    try {
      const data=await rpc('sq_admin_delivery_orders',{p_limit:250,p_offset:append?adminOrders.length:0});if(seq!==adminSeq)return;
      adminOrders=append?[...adminOrders,...data.items]:data.items;
      const groups=new Map();for(const o of adminOrders){const key=o.delivery_id||`user:${o.user_id}`;if(!groups.has(key))groups.set(key,[]);groups.get(key).push(o);}
      root.innerHTML=[...groups.entries()].map(([key,items])=>renderDeliveryCard(key,items)).join('')||'<div class="admin-empty"><strong>All caught up</strong>No active orders or deliveries.</div>';
      if(adminOrders.length<Number(data.total))root.insertAdjacentHTML('beforeend','<button class="admin-load-more" data-deliveries-more>Load more orders</button>');
    }catch(e){if(seq===adminSeq)root.innerHTML=errorBox('Deliveries unavailable',e)+'<button class="admin-secondary-button" data-deliveries-retry>Retry</button>';}
  }
  async function createDelivery(button) {
    const root=button.closest('[data-delivery-group]'),ids=$$('[data-group-order]:checked',root).map(i=>Number(i.value));
    if(ids.length<2)return message('Select at least two unsent orders for this customer.','error');
    if(!await confirmAction(`Send these ${ids.length} orders together in one Steam offer?`,{title:'Create shared delivery?',confirmText:'Group orders'}))return;
    button.disabled=true;
    try{await rpc('sq_admin_create_delivery',{p_order_ids:ids});await adminDeliveries();message('Shared delivery created. Copy its Steam message when you send the offer.','success');}
    catch(e){message(e.message,'error');}finally{button.disabled=false;}
  }
  async function updateDelivery(form) {
    const target=form.dataset.target,until=$('[name=until]',form)?.value||null,offer=$('[name=offer]',form)?.value.trim()||null;
    if(until&&(Number.isNaN(new Date(until).getTime())||new Date(until)<=new Date()))return message('Choose a future Steam unlock time.','error');
    if(offer&&!isValidSteamTradeOfferUrl(offer))return message('Use a valid Steam offer URL.','error');
    const grouped=!!form.dataset.deliveryUpdate;
    const items=grouped?adminOrders.filter(o=>o.delivery_id===form.dataset.deliveryUpdate):adminOrders.filter(o=>String(o.id)===form.dataset.singleUpdate);
    if(items.some(o=>o.status==='trade_locked')&&target==='ready_to_trade'&&items.some(o=>new Date(o.trade_locked_until)>new Date()))return message('Wait for the recorded trade lock to expire.','error');
    const warning=target==='trade_locked'?'Confirm the item was purchased and check Steam’s actual tradable time.':target==='trade_sent'?'Confirm the Steam offer was actually sent. The normal refund flow is then unavailable.':target==='completed'?'Confirm the customer accepted the Steam offer. This closes the order.':`Apply ${status(target)} to ${items.length} order${items.length===1?'':'s'}?`;
    if(!await confirmAction(warning,{title:grouped?'Update shared delivery?':'Update order?',confirmText:'Confirm step'}))return;
    const b=$('[type=submit]',form);b.disabled=true;
    try {
      if(grouped)await rpc('sq_admin_delivery_update',{p_delivery_id:form.dataset.deliveryUpdate,p_status:target,p_lock_until:until?new Date(until).toISOString():null,p_trade_offer_url:offer,p_note:null});
      else await rpc('sq_admin_update_order',{p_request_id:Number(form.dataset.singleUpdate),p_status:target,p_admin_note:items[0]?.admin_note||null,p_trade_offer_url:offer,p_trade_locked_until:until?new Date(until).toISOString():null});
      if(items[0])sb.functions.invoke('reward-order-status-notify',{body:{request_id:items[0].id}}).then(({error})=>{if(error)message('Status saved; customer email needs a retry.','info');}).catch(()=>{});
      await Promise.allSettled([adminDeliveries(),window.SQ15Admin?.refresh()]);message(grouped?'Delivery updated.':'Order updated.','success');
    }catch(e){message(e.message,'error');}finally{b.disabled=false;}
  }
  async function mountOrderTools(item) {
    const root=$('#adminOrderUpdateForm');if(!root)return;
    function lockDefault(){const select=$('#drawerOrderStatus'),input=$('#drawerOrderLockUntil');
      if(select?.value==='trade_locked'&&input&&!input.value){input.value=toLocal(Date.now()+192*3600000);input.dataset.defaultLock='true';}}
    $('#drawerOrderStatus')?.addEventListener('change',lockDefault);lockDefault();
    $('#drawerOrderLockUntil')?.addEventListener('input',e=>delete e.target.dataset.defaultLock);
    root.insertAdjacentHTML('beforebegin',`<div class="sq15-button-row"><button type="button" class="admin-secondary-button" data-go-deliveries>Open deliveries</button></div><div class="sq15-fulfil-controls">${steamNote([item],item.delivery_id)}</div><div id="sq15TradeReview"></div>`);
    if(terminal(item.status)||item.status==='trade_sent')return;
    try{const {data,error}=await sb.from('profiles').select('steam_trade_url').eq('id',item.user_id).maybeSingle();if(error)throw error;
      if($('#adminOrderUpdateForm')!==root)return;
      if(data?.steam_trade_url!==item.steam_trade_url)$('#sq15TradeReview').innerHTML=`<section class="sq15-notice"><strong>Trade link changed — review required</strong><p>The order still holds its old delivery address. Already-sent offers are never redirected.</p><code>${safe(data?.steam_trade_url||'Current trade link is missing')}</code><button type="button" class="admin-primary-button" data-review-trade="${item.id}" data-expected-trade="${safe(data?.steam_trade_url||'')}" ${!data?.steam_trade_url?'disabled':''}>Review & use current link</button></section>`;
    }catch(e){$('#sq15TradeReview').innerHTML=errorBox('Could not check current trade link',e);}
  }
  async function userEarnings(uid) {
    const root=$('#adminUserEarningMetrics');if(!root)return;
    try{const data=await rpc('sq_admin_user_earnings',{p_user_id:uid});if(root!==$('#adminUserEarningMetrics'))return;
      root.innerHTML=data.map(s=>`<article><strong>${safe(names[s.source])}</strong><dl><div><dt>Verified rewards</dt><dd>${n(s.verified_rewards)}</dd></div><div><dt>Verified coins</dt><dd>${n(s.coins)}</dd></div><div><dt>Recorded opens</dt><dd>${n(s.opens)}</dd></div><div><dt>Provider views</dt><dd>${n(s.views)}</dd></div><div><dt>Reversed rewards</dt><dd>${n(s.reversed)}</dd></div></dl></article>`).join('');
    }catch(e){root.innerHTML=errorBox('Provider metrics unavailable',e);}
  }
  async function ownerEarnings() {
    const root=$('#ownerEarningStats');if(!root)return;const seq=++earningsSeq;
    root.innerHTML='<div class="admin-empty">Loading provider evidence…</div>';
    try{const data=await rpc('sq_owner_earning_stats',{p_days:Number($('#earningStatsPeriod')?.value??30)});if(seq!==earningsSeq)return;
      const metrics=s=>`<dl><div><dt>Recorded opens</dt><dd>${n(s.opens)}</dd></div><div><dt>Provider views</dt><dd>${n(s.views)}</dd></div><div><dt>Verified reward events</dt><dd>${n(s.verified_rewards)}</dd></div><div><dt>Users earning rewards</dt><dd>${n(s.completing_users)}</dd></div><div><dt>Verified coins</dt><dd>${n(s.coins)}</dd></div><div><dt>Reversed / pending</dt><dd>${n(s.reversed)} / ${n(s.pending)}</dd></div></dl>`;
      const cash=s=>`${s.reported_revenue_usd==null?'Not reported':`$${Number(s.reported_revenue_usd).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:4})}`}<small>${n(s.revenue_unknown)} verified events without reported USD${s.revenue_unknown?' · partial total':''}</small>`;
      root.innerHTML=`<section class="admin-card sq15-earning-total"><div><span class="admin-eyebrow">All earning sources · ${data.days?`last ${data.days} days`:'all time'}</span><h2>Reported callback revenue</h2><strong class="sq15-revenue">${cash(data.totals)}</strong></div>${metrics(data.totals)}</section><div class="sq15-earning-grid">${data.sources.map(s=>`<section class="admin-card sq15-earning-card"><h2>${safe(names[s.source])}</h2><strong class="sq15-revenue">${cash(s)}</strong>${metrics(s)}</section>`).join('')}</div><aside class="sq15-notice">${safe(data.note)} Screen-out compensation can be a verified reward event; it is not necessarily a full survey completion. <a href="#finance" data-admin-view-link="finance">Open Finance & funding</a>.</aside><details class="admin-card sq15-daily"><summary>Daily recorded activity (up to 90 days)</summary><div class="sq15-daily-table">${data.daily.map(d=>`<div><span>${safe(d.day)}</span><strong>${safe(names[d.source])}</strong><span>${n(d.verified_rewards)} rewards</span><span>${d.reported_revenue_usd==null?'USD not reported':`$${Number(d.reported_revenue_usd).toFixed(4)}`}</span></div>`).join('')||'<p>No provider reward records in this period.</p>'}</div></details>`;
    }catch(e){if(seq===earningsSeq)root.innerHTML=errorBox('Earnings statistics unavailable',e);}
  }
  async function timewallHealth() {
    const root=$('#timewallHealth');if(!root)return;
    root.textContent='Checking configuration and recorded callbacks…';
    try {
      const [feed,statusResult]=await Promise.all([sb.functions.invoke('survey-feed'),rpc('sq_admin_timewall_status')]);
      if(feed.error)throw feed.error;
      const ready=!!feed.data?.timewall_launch_ready,events=Number(statusResult.completed||0);
      root.innerHTML=`<div class="sq15-timewall-check"><div><strong>${ready?'Wall launch configured':'Wall launch not configured'}</strong><p>${safe(feed.data?.timewall_configuration||'Configuration unavailable.')}</p></div><div><strong>${n(events)} verified TimeWall credits</strong><p>${events?`Latest credit: ${date(statusResult.last_completed_at)}`:'No verified TimeWall reward has reached this database yet.'} · ${n(statusResult.reversed)} reversed</p></div><p>A launch link alone does not prove that TimeWall is sending callbacks. Compare a real test transaction in its publisher dashboard with the coin ledger here.</p></div>`;
    }catch(e){root.innerHTML=errorBox('Connection check unavailable',e);}
  }
  function prepare() {
    document.documentElement.classList.add('sq15');
    if(bound)return;bound=true;
    document.addEventListener('click',async e=>{
      const b=e.target.closest('button,a');if(!b)return;
      if(b.matches('[data-provider-open]')){if(b.getAttribute('aria-disabled')==='true')return e.preventDefault();if(b.tagName==='BUTTON'){e.preventDefault();launchProvider(b.dataset.providerOpen,true);}else{if(!urls.get(b.dataset.providerOpen)||providerUser!==currentUser?.id)return e.preventDefault();launchProvider(b.dataset.providerOpen);}}
      if(b.matches('[data-provider-retry]')){providerUser=null;await initProviders();}
      if(b.matches('[data-orders-filter]')){customer.filter=b.dataset.ordersFilter;$$('[data-orders-filter]').forEach(x=>{x.classList.toggle('active',x===b);x.setAttribute('aria-pressed',String(x===b));});await myOrders();}
      if(b.matches('[data-orders-more]'))await myOrders(true);
      if(b.matches('[data-orders-retry]'))await myOrders();
      if(b.matches('[data-create-delivery]'))await createDelivery(b);
      if(b.matches('[data-deliveries-retry]'))await adminDeliveries();
      if(b.matches('[data-deliveries-more]'))await adminDeliveries(true);
      if(b.matches('[data-open-fulfilment-order]'))window.SQ15Admin?.openOrder(Number(b.dataset.openFulfilmentOrder));
      if(b.matches('[data-go-deliveries]')){window.SQ15Admin?.closeDrawer();window.SQ15Admin?.showView('deliveries');}
      if(b.matches('[data-copy-note],[data-copy-url]')){const card=b.closest('.sq15-fulfil-controls');const field=b.matches('[data-copy-note]')?$('.sq15-steam-note',card):$('.sq15-trade-address code',card);try{await navigator.clipboard.writeText(field.value||field.textContent);message(b.matches('[data-copy-note]')?'Steam message copied.':'Trade link copied.','success');}catch{if(field.select){field.select();message('Select and copy the highlighted message.','info');}else message('Clipboard unavailable.','error');}}
      if(b.matches('[data-review-trade]')){if(!await confirmAction('Confirm you have checked the new Steam trade link and account. This updates only this unsent order’s delivery address.',{title:'Review changed trade URL?',confirmText:'Use reviewed link'}))return;b.disabled=true;try{await rpc('sq_admin_review_trade_url',{p_order_id:Number(b.dataset.reviewTrade),p_expected_url:b.dataset.expectedTrade});await window.SQ15Admin?.refresh();await window.SQ15Admin?.openOrder(Number(b.dataset.reviewTrade));message('Current trade URL reviewed.','success');}catch(err){message(err.message,'error');}finally{b.disabled=false;}}
      if(b.matches('[data-review-delivery]')){if(!await confirmAction('Confirm the new Steam trade link and customer account have been checked. Apply it to all unsent orders in this delivery? Sent offers stay unchanged.',{title:'Review delivery address?',confirmText:'Apply reviewed link'}))return;b.disabled=true;try{await rpc('sq_admin_review_delivery_trade_url',{p_delivery_id:b.dataset.reviewDelivery,p_expected_url:b.dataset.expectedTrade});await Promise.allSettled([adminDeliveries(),window.SQ15Admin?.refresh()]);message('Unsent delivery addresses reviewed.','success');}catch(err){message(err.message,'error');}finally{b.disabled=false;}}
      if(b.matches('[data-earning-refresh]'))await ownerEarnings();
      if(b.matches('[data-timewall-check]'))await timewallHealth();
    });
    document.addEventListener('change',e=>{if(e.target.matches('[data-select-group]'))$$('[data-group-order]',e.target.closest('[data-delivery-group]')).forEach(c=>c.checked=e.target.checked);if(e.target.id==='earningStatsPeriod')ownerEarnings();});
    document.addEventListener('submit',e=>{if(e.target.matches('[data-delivery-update],[data-single-update]')){e.preventDefault();updateDelivery(e.target).catch(err=>message(err.message,'error'));}});
    // The safe-area belongs to the entire interactive header, including PWA cutouts.
    document.addEventListener('focusin',e=>{if(e.target.matches('input,textarea'))document.body.classList.add('sq15-keyboard');});
    document.addEventListener('focusout',()=>setTimeout(()=>{if(!document.activeElement?.matches('input,textarea'))document.body.classList.remove('sq15-keyboard');},50));
  }
  async function init(){prepare();await Promise.allSettled([initProviders(),myOrders()]);}
  window.SQ15={prepare,init,recordOpen:s=>record(s,'open'),recordView:s=>record(s,'view'),configureProviders,resetProviders,myOrders,augmentOrder,mountOrderTools,userEarnings,adminView:v=>v==='deliveries'?adminDeliveries():v==='earnings'?Promise.allSettled([ownerEarnings(),timewallHealth()]):null};
})();
