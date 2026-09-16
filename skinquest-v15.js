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
    for(const source of ['timewall_surveys','timewall_earn']) {
      const frame=$(`[data-timewall-frame="${source}"]`);if(frame)frame.src='about:blank';
      $(`[data-timewall-stage="${source}"]`)?.classList.add('hidden');
      $$(`[data-provider-open="${source}"]`).forEach(b=>{b.removeAttribute('href');b.disabled=true;});
    }
  }
  function safeTimewall(value,uid) {
    try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='timewall.io'&&
      u.searchParams.get('uid')===uid&&/^[a-zA-Z0-9_-]{8,100}$/.test(u.searchParams.get('oid')||'')?u.toString():null;}catch{return null;}
  }
  function configureProviders(data,uid) {
    if(currentUser?.id!==uid)return;
    if(providerUser!==uid){resetProviders();providerUser=uid;}
    for(const [source,key] of [['timewall_surveys','timewall_wall_url'],['timewall_earn','timewall_earn_url']]) {
      const url=safeTimewall(data?.[key],uid),panel=$(`[data-timewall-panel="${source}"]`);if(!panel)continue;
      if(url){urls.set(source,url);panel.classList.remove('hidden');
        $$(`[data-provider-open="${source}"]`).forEach(b=>{b.disabled=false;if(b.tagName==='A')b.href=url;});
        $(`[data-timewall-empty="${source}"]`)?.classList.add('hidden');
        $(`[data-timewall-controls="${source}"]`)?.classList.remove('hidden');
        if(source==='timewall_surveys')$('#timewallProviderLink')?.classList.remove('hidden');
      }else{urls.delete(source);$(`[data-timewall-controls="${source}"]`)?.classList.add('hidden');
        const empty=$(`[data-timewall-empty="${source}"]`);empty?.classList.remove('hidden');}
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
      root.innerHTML=group(customer.items).map(([key,items])=>`<section class="panel sq15-delivery"><header><div><span class="pill">${key.startsWith('ungrouped:')?'Individual orders':'Grouped Steam delivery'}</span><h2>${safe(items[0].delivery_label||'Not assigned to a shared delivery yet')}</h2><p class="muted">${n(items.length)} loaded item${items.length===1?'':'s'} · ${n(items.reduce((v,o)=>v+Number(o.points_coins||o.points_cost),0))} saved coins${key.startsWith('ungrouped:')?'':' · may be sent in the same Steam offer'}</p></div></header>${items.map(orderRow).join('')}</section>`).join('')||errorBox('No orders in this view','Choose a reward to start your first order.');
      if(customer.items.length<customer.total)root.insertAdjacentHTML('beforeend',`<button class="button button-ghost" data-orders-more>Load more orders (${n(customer.items.length)} / ${n(customer.total)})</button>`);
    }catch(e){if(seq===ordersSeq)root.innerHTML=errorBox('Could not load orders',e)+'<button class="button button-ghost" data-orders-retry>Try again</button>';}
  }
  function augmentOrder(item) {
    const root=$('#orderDetail');if(!root||!item)return;
    if(item.trade_url_needs_review)root.insertAdjacentHTML('afterbegin','<aside class="sq15-notice">Your trade link changed. Staff will review the new link before sending this order. An already-sent offer is not redirected.</aside>');
    if(item.delivery_id&&item.delivery_items?.length)root.insertAdjacentHTML('beforeend',`<section class="panel sq15-delivery"><span class="pill">Grouped Steam delivery</span><h2>${safe(item.delivery_label)}</h2><p class="muted">These orders are grouped for fulfilment. Each retains its own saved coin price and status.</p>${item.delivery_items.map(s=>`<a class="sq15-sibling" href="/orders/${s.id}"><span><strong>${safe(s.reward_name)}</strong><small>${safe(s.order_number)} · ${n(s.coins)} coins</small></span>${badge(s.status)}</a>`).join('')}</section>`);
  }
  async function adminDeliveries(append=false) {
    const root=$('#adminDeliveries');if(!root)return;
    const seq=++adminSeq;if(!append)root.innerHTML='<div class="admin-empty">Loading fulfilment groups…</div>';
    try{const data=await rpc('sq_admin_delivery_orders',{p_limit:250,p_offset:append?adminOrders.length:0});if(seq!==adminSeq)return;
      adminOrders=append?[...adminOrders,...data.items]:data.items;
      const groups=new Map();for(const o of adminOrders){const key=o.delivery_id||`user:${o.user_id}`;if(!groups.has(key))groups.set(key,[]);groups.get(key).push(o);}
      root.innerHTML=[...groups.entries()].map(([key,items])=>{
        const first=items[0], grouped=!!first.delivery_id, eligible=items.filter(o=>o.status!=='trade_sent');
        return `<section class="admin-card sq15-admin-delivery" data-delivery-group="${safe(key)}"><header><div><span class="admin-eyebrow">${grouped?'Grouped Steam delivery':'Ungrouped customer orders'}</span><h2>${safe(first.steam_name||first.username||first.user_id)}</h2><p>${safe(first.contact_email||'Contact email not recorded')} · ${items.length} loaded items · ${n(items.reduce((v,o)=>v+Number(o.points_coins||o.points_cost),0))} saved coins</p>${grouped?`<small>Delivery ${safe(first.delivery_id.slice(0,8))} · ${safe(first.delivery_label)}</small>`:''}</div>${!grouped&&eligible.length?'<label class="sq15-check"><input type="checkbox" data-select-group />Select unsent orders</label>':''}</header>
        <div>${items.map(o=>`<div class="sq15-admin-order">${!grouped&&o.status!=='trade_sent'?`<input aria-label="Select ${safe(o.order_number)}" type="checkbox" value="${o.id}" data-group-order />`:'<span></span>'}<button class="sq15-order-open" type="button" data-open-fulfilment-order="${o.id}"><strong>${safe(o.reward_name)}</strong><small>${safe(o.order_number)} · ${n(o.points_coins||o.points_cost)} coins${o.trade_url_needs_review?' · TRADE LINK CHANGED':''}</small></button><div>${badge(o.status)}${o.status==='trade_locked'&&o.trade_locked_until?`<small>${safe(formatTradeLockRemaining(o.trade_locked_until))} · ${date(o.trade_locked_until)}</small>`:''}</div></div>`).join('')}</div>
        ${grouped&&items.some(o=>o.trade_url_needs_review)?`<div class="sq15-notice"><strong>Trade link changed</strong><p>Review the new address before sending this delivery.</p><code>${safe(first.current_trade_url||'Missing trade link')}</code><button class="admin-secondary-button" type="button" data-review-delivery="${safe(first.delivery_id)}" data-expected-trade="${safe(first.current_trade_url||'')}" ${!first.current_trade_url?'disabled':''}>Review & use current link for unsent items</button></div>`:''}
        ${grouped?`<form class="sq15-delivery-form" data-delivery-update="${safe(first.delivery_id)}"><label>Apply to active items<select name="status"><option value="trade_locked">Purchased → Trade locked</option><option value="ordered">Awaiting purchase</option><option value="reviewing">Reviewing</option><option value="ready_to_trade">Ready to trade</option><option value="trade_sent">Trade sent</option><option value="completed">Completed</option></select></label><label>Custom lock end (optional)<input name="until" type="datetime-local" /><small>Blank = exactly 192 hours (8 days) from saving. Verify Steam's actual time.</small></label><label>Steam offer URL (optional)<input name="offer" maxlength="500" placeholder="https://steamcommunity.com/tradeoffer/123456789/" /></label><label>Customer update (optional)<input name="note" maxlength="2000" placeholder="Same update for every active item" /></label><div class="sq15-button-row"><button class="admin-primary-button" type="submit">Update delivery</button><button class="admin-secondary-button" type="button" data-copy-delivery="${safe(first.delivery_id)}">Copy trade message</button></div></form>`:`<div class="sq15-button-row"><button class="admin-primary-button" type="button" data-create-delivery ${!eligible.length?'disabled':''}>Group selected orders</button><small>One customer per delivery. Coins and existing lock dates stay unchanged.</small></div>`}</section>`;
      }).join('')||'<div class="admin-empty">No active deliveries or orders.</div>';
      if(adminOrders.length<Number(data.total))root.insertAdjacentHTML('beforeend','<button class="admin-load-more" data-deliveries-more>Load more fulfilment items</button>');
      window.refreshSkinQuestSelects?.();
    }catch(e){if(seq===adminSeq)root.innerHTML=errorBox('Deliveries unavailable',e)+'<button class="admin-secondary-button" data-deliveries-retry>Retry</button>';}
  }
  async function createDelivery(button) {
    const root=button.closest('[data-delivery-group]'),ids=$$('[data-group-order]:checked',root).map(i=>Number(i.value));
    if(!ids.length)return message('Select the orders to send together.','error');
    if(!await confirmAction(`Group ${ids.length} selected orders for the same customer? Their prices and status history are preserved.`,{title:'Create shared delivery?',confirmText:'Group orders'}))return;
    button.disabled=true;try{await rpc('sq_admin_create_delivery',{p_order_ids:ids});await adminDeliveries();message('Orders grouped. You can now apply a shared purchase lock.','success');}catch(e){message(e.message,'error');}finally{button.disabled=false;}
  }
  async function updateDelivery(form) {
    const input=new FormData(form),target=input.get('status'),until=input.get('until'),offer=String(input.get('offer')||'').trim();
    if(until&&(Number.isNaN(new Date(until).getTime())||new Date(until).getTime()<=Date.now()))return message('Choose a future unlock time.','error');
    if(offer&&!isValidSteamTradeOfferUrl(offer))return message('Use a valid Steam offer URL.','error');
    const text=target==='trade_locked'?'Confirm all active items in this delivery have been purchased. A blank date sets the shared lock to exactly eight days from saving. This is an operational default: check Steam’s actual tradable time.':target==='trade_sent'?'Confirm the Steam offer containing these active items was actually sent. Sent orders cannot be refunded through the normal workflow.':target==='completed'?'Confirm these sent items were actually delivered. This closes every active item.':`Apply ${status(target)} to every active item? If one item is incompatible, nothing will be changed.`;
    if(!await confirmAction(text,{title:'Update entire delivery?',confirmText:'Confirm update'}))return;
    const b=$('[type=submit]',form);b.disabled=true;
    try{await rpc('sq_admin_delivery_update',{p_delivery_id:form.dataset.deliveryUpdate,p_status:target,p_lock_until:until?new Date(until).toISOString():null,p_trade_offer_url:offer||null,p_note:String(input.get('note')||'').trim()||null});
      const items=adminOrders.filter(o=>o.delivery_id===form.dataset.deliveryUpdate&&!terminal(o.status));
      if(items[0])sb.functions.invoke('reward-order-status-notify',{body:{request_id:items[0].id}}).then(({error})=>{if(error)message('Delivery saved, but its email update needs a retry.','info');}).catch(()=>{});
      await Promise.allSettled([adminDeliveries(),window.SQ15Admin?.refresh()]);message('Delivery updated. Every item retains its own history.','success');
    }catch(e){message(e.message,'error');}finally{b.disabled=false;}
  }
  async function mountOrderTools(item) {
    const root=$('#adminOrderUpdateForm');if(!root)return;
    function lockDefault(){const select=$('#drawerOrderStatus'),input=$('#drawerOrderLockUntil');
      if(select?.value==='trade_locked'&&input&&!input.value){input.value=toLocal(Date.now()+192*3600000);input.dataset.defaultLock='true';}}
    $('#drawerOrderStatus')?.addEventListener('change',lockDefault);lockDefault();
    $('#drawerOrderLockUntil')?.addEventListener('input',e=>delete e.target.dataset.defaultLock);
    root.insertAdjacentHTML('beforebegin',`<div class="sq15-button-row"><button type="button" class="admin-secondary-button" data-go-deliveries>Manage shared deliveries</button></div><div id="sq15TradeReview"></div>`);
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
  function prepare() {
    document.documentElement.classList.add('sq15');
    if($('#redeemHistory')&&!$('#sq15OrdersLink'))$('#redeemHistory').closest('.panel')?.insertAdjacentHTML('afterbegin','<a id="sq15OrdersLink" class="sq15-text-link" href="/orders">Open all orders & deliveries →</a>');
    if(bound)return;bound=true;
    document.addEventListener('click',async e=>{
      const b=e.target.closest('button,a');if(!b)return;
      if(b.matches('[data-provider-open]')){if(b.getAttribute('aria-disabled')==='true')return e.preventDefault();if(b.tagName==='BUTTON'){e.preventDefault();launchProvider(b.dataset.providerOpen,true);}else{if(!urls.get(b.dataset.providerOpen))return e.preventDefault();launchProvider(b.dataset.providerOpen);}}
      if(b.matches('[data-provider-retry]')){providerUser=null;await initProviders();}
      if(b.matches('[data-orders-filter]')){customer.filter=b.dataset.ordersFilter;$$('[data-orders-filter]').forEach(x=>{x.classList.toggle('active',x===b);x.setAttribute('aria-pressed',String(x===b));});await myOrders();}
      if(b.matches('[data-orders-more]'))await myOrders(true);
      if(b.matches('[data-orders-retry]'))await myOrders();
      if(b.matches('[data-create-delivery]'))await createDelivery(b);
      if(b.matches('[data-deliveries-retry]'))await adminDeliveries();
      if(b.matches('[data-deliveries-more]'))await adminDeliveries(true);
      if(b.matches('[data-open-fulfilment-order]'))window.SQ15Admin?.openOrder(Number(b.dataset.openFulfilmentOrder));
      if(b.matches('[data-go-deliveries]')){window.SQ15Admin?.closeDrawer();window.SQ15Admin?.showView('deliveries');}
      if(b.matches('[data-copy-delivery]')){try{await navigator.clipboard.writeText(`SkinQuest delivery #${b.dataset.copyDelivery.slice(0,8)}. Please verify the items before accepting.`);message('Trade message copied.','success');}catch{message('Clipboard unavailable.','error');}}
      if(b.matches('[data-review-trade]')){if(!await confirmAction('Confirm you have checked the new Steam trade link and account. This updates only this unsent order’s delivery address.',{title:'Review changed trade URL?',confirmText:'Use reviewed link'}))return;b.disabled=true;try{await rpc('sq_admin_review_trade_url',{p_order_id:Number(b.dataset.reviewTrade),p_expected_url:b.dataset.expectedTrade});await window.SQ15Admin?.refresh();await window.SQ15Admin?.openOrder(Number(b.dataset.reviewTrade));message('Current trade URL reviewed.','success');}catch(err){message(err.message,'error');}finally{b.disabled=false;}}
      if(b.matches('[data-review-delivery]')){if(!await confirmAction('Confirm the new Steam trade link and customer account have been checked. Apply it to all unsent orders in this delivery? Sent offers stay unchanged.',{title:'Review delivery address?',confirmText:'Apply reviewed link'}))return;b.disabled=true;try{await rpc('sq_admin_review_delivery_trade_url',{p_delivery_id:b.dataset.reviewDelivery,p_expected_url:b.dataset.expectedTrade});await Promise.allSettled([adminDeliveries(),window.SQ15Admin?.refresh()]);message('Unsent delivery addresses reviewed.','success');}catch(err){message(err.message,'error');}finally{b.disabled=false;}}
      if(b.matches('[data-earning-refresh]'))await ownerEarnings();
    });
    document.addEventListener('change',e=>{if(e.target.matches('[data-select-group]'))$$('[data-group-order]',e.target.closest('[data-delivery-group]')).forEach(c=>c.checked=e.target.checked);if(e.target.id==='earningStatsPeriod')ownerEarnings();});
    document.addEventListener('submit',e=>{if(e.target.matches('[data-delivery-update]')){e.preventDefault();updateDelivery(e.target).catch(err=>message(err.message,'error'));}});
    // The safe-area belongs to the entire interactive header, including PWA cutouts.
    document.addEventListener('focusin',e=>{if(e.target.matches('input,textarea'))document.body.classList.add('sq15-keyboard');});
    document.addEventListener('focusout',()=>setTimeout(()=>{if(!document.activeElement?.matches('input,textarea'))document.body.classList.remove('sq15-keyboard');},50));
  }
  async function init(){prepare();await Promise.allSettled([initProviders(),myOrders()]);}
  window.SQ15={prepare,init,recordOpen:s=>record(s,'open'),recordView:s=>record(s,'view'),configureProviders,resetProviders,myOrders,augmentOrder,mountOrderTools,userEarnings,adminView:v=>v==='deliveries'?adminDeliveries():v==='earnings'?ownerEarnings():null};
})();
