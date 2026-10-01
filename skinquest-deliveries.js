/* SkinQuest v15.2.0: one customer, one checklist, one Steam offer. */
(() => {
  'use strict';
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const safe = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const label = s => typeof formatStatus === 'function' ? formatStatus(s) : s.replaceAll('_', ' ');
  const state = {customers:[], total:0, stats:{}, current:null, selected:new Set(), busy:false, loading:false, seq:0, search:'', filter:'all', bound:false, timer:null};
  const current = () => state.customers.find(c => c.user_id === state.current);
  const chosen = () => (current()?.items || []).filter(o => state.selected.has(String(o.id)));
  const expected = items => Object.fromEntries(items.map(o => [String(o.id), {status:o.status, updated_at:o.updated_at}]));
  const message = (t,k='info') => showMessage(t,k);
  async function rpc(name,args) { const {data,error} = await sb.rpc(name,args); if(error) throw error; return data; }
  const ready = o => o.status === 'ready_to_trade' || (['pending','reviewing','ordered'].includes(o.status) && o.fulfillment_mode === 'stocked') || (o.status === 'trade_locked' && o.trade_locked_until && new Date(o.trade_locked_until) <= new Date());
  const purchase = o => o.fulfillment_mode === 'orderable' && ['pending','reviewing','ordered'].includes(o.status);
  function validTrade(value) {
    try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password && !u.port && ['steamcommunity.com','www.steamcommunity.com'].includes(u.hostname) && /^\/tradeoffer\/new\/?$/.test(u.pathname) && /^\d+$/.test(u.searchParams.get('partner') || '') && /^[A-Za-z0-9_-]+$/.test(u.searchParams.get('token') || ''); } catch { return false; }
  }
  function offerMessage(items) {
    if (!items.length) return '';
    const ref = `SkinQuest ${items.length === 1 ? 'order' : 'orders'} ${items.map(o => o.order_number).join(', ')}`;
    const text = `${ref} - ${items.length === 1 ? items[0].reward_name : `${items.length} items`}`;
    if (text.length <= 125) return text;
    if (ref.length <= 125) return ref;
    const groups = new Set(items.map(o => o.delivery_id));
    return groups.size === 1 && items[0].delivery_id
      ? `SkinQuest delivery ${items[0].delivery_id.slice(0,8)} - ${items.length} orders. Verify items on SkinQuest.`
      : `SkinQuest orders ${items[0].order_number} + ${items.length-1} more. Verify the complete item list on SkinQuest.`.slice(0,125);
  }
  function selectItems(predicate) {
    state.selected.clear();
    const items = current()?.items || [];
    // Shared offers are selected as a unit, including members at a different stage.
    for (const o of items.filter(predicate)) {
      const group = o.delivery_id ? items.filter(x => x.delivery_id === o.delivery_id) : [o];
      const extra = group.filter(x => !state.selected.has(String(x.id)));
      if (state.selected.size + extra.length <= 100) extra.forEach(x => state.selected.add(String(x.id)));
    }
  }
  function chooseCustomer(id) {
    state.current = id;
    selectItems(o => ready(o) && !o.trade_url_needs_review);
    if (!state.selected.size) selectItems(o => o.status !== 'trade_sent');
    if (!state.selected.size) selectItems(o => o.status === 'trade_sent');
  }
  async function load(append=false, preserve=true) {
    bind();
    const root = $('#adminDeliveries'); if (!root) return;
    const seq = ++state.seq, oldId = state.current, oldIndex = state.customers.findIndex(c => c.user_id === oldId);
    state.loading = true;
    if (!state.customers.length) root.innerHTML = '<div class="admin-empty">Loading the customer delivery queue…</div>';
    $('#deliveryQueueStatus').textContent = 'Refreshing…';
    try {
      const data = await rpc('sq_admin_delivery_queue', {p_search:state.search || null,p_filter:state.filter,p_limit:40,p_offset:append ? state.customers.length : 0});
      if (seq !== state.seq) return;
      state.customers = append ? [...state.customers, ...data.customers] : data.customers;
      state.total = Number(data.total); state.stats = data.stats || {};
      if (!current()) chooseCustomer(state.customers[Math.min(Math.max(oldIndex,0),state.customers.length-1)]?.user_id || null);
      else if (!preserve) chooseCustomer(oldId);
      else {
        const ids = new Set(current().items.map(o => String(o.id)));
        state.selected = new Set([...state.selected].filter(id => ids.has(id)));
        if (!state.selected.size) chooseCustomer(oldId);
      }
      state.loading = false; render();
    } catch (e) {
      if (seq !== state.seq) return;
      state.loading = false;
      root.innerHTML = `<div class="admin-empty"><strong>Could not load deliveries</strong><p>${safe(e.message)}</p><span>Apply skinquest_upgrade_existing_to_v15_2_0.sql, then refresh.</span><button type="button" class="admin-secondary-button" data-dq-refresh>Retry</button></div>`;
      $('#deliveryQueueStatus').textContent = 'Refresh needed';
    }
  }
  function render() {
    const root = $('#adminDeliveries'); if (!root) return;
    const stats = state.stats;
    $('#deliveryQueueStatus').textContent = `${stats.orders || 0} orders · ${stats.customers || 0} customers`;
    $('#deliveryQueueStats').innerHTML = [['ready','Ready now',stats.ready],['purchase','To purchase',stats.purchase],['locked','Trade locked',stats.locked],['sent','Awaiting acceptance',stats.sent],['review','Link review',stats.review]].map(([filter,text,count]) => `<button type="button" class="dq-stat ${state.filter === filter ? 'active' : ''}" data-dq-filter="${filter}" aria-pressed="${state.filter === filter}"><strong>${count || 0}</strong><span>${text}</span></button>`).join('');
    if (!state.customers.length) { root.innerHTML = `<div class="admin-empty"><strong>${state.search || state.filter !== 'all' ? 'No matching customers' : 'All caught up'}</strong><p>${state.search || state.filter !== 'all' ? 'Change the search or choose All active.' : 'There are no active reward deliveries.'}</p></div>`; return; }
    root.innerHTML = `<div class="dq-layout"><aside class="admin-card dq-queue" aria-label="Delivery customers"><div class="dq-queue-title"><strong>Customer queue</strong><small>${state.customers.length} / ${state.total}</small></div>${state.customers.map(c => `<button type="button" class="dq-customer ${c.user_id === state.current ? 'active' : ''}" data-dq-customer="${safe(c.user_id)}" aria-pressed="${c.user_id === state.current}" ${state.busy ? 'disabled' : ''}><strong>${safe(c.name)}</strong><span>${c.order_count} item${Number(c.order_count) === 1 ? '' : 's'}${c.ready_count ? ` · ${c.ready_count} ready` : ''}${c.sent_count ? ` · ${c.sent_count} sent` : ''}</span>${c.review_count ? '<small>Trade link needs review</small>' : ''}</button>`).join('')}${state.customers.length < state.total ? '<button type="button" class="admin-load-more" data-dq-more>Load more customers</button>' : ''}</aside><section id="deliveryCustomerWorkspace" class="admin-card dq-workspace"></section></div>`;
    renderWorkspace();
  }
  function renderWorkspace() {
    const root = $('#deliveryCustomerWorkspace'), c = current(); if (!root || !c) return;
    const groups = new Map();
    for (const o of c.items) { const key = o.delivery_id || 'individual'; if (!groups.has(key)) groups.set(key,[]); groups.get(key).push(o); }
    const position = state.customers.indexOf(c);
    root.innerHTML = `<header class="dq-workspace-head"><div><span class="admin-eyebrow">Customer ${position+1} of ${state.total}</span><h2>${safe(c.name)}</h2><p>${safe(c.email || 'No contact email recorded')} · ${c.order_count} active item${Number(c.order_count) === 1 ? '' : 's'}</p></div><div class="dq-navigation"><button type="button" class="admin-secondary-button" data-dq-nav="-1" ${position === 0 || state.busy ? 'disabled' : ''} aria-label="Previous customer">←</button><button type="button" class="admin-secondary-button" data-dq-nav="1" ${position === state.customers.length-1 || state.busy ? 'disabled' : ''} aria-label="Next customer">Next customer →</button></div></header><div class="dq-select-tools"><span>Select:</span>${[['ready','Ready now'],['purchase','To purchase'],['unsent','All unsent'],['sent','Sent offers'],['none','Clear']].map(([v,t]) => `<button type="button" class="admin-text-button" data-dq-select="${v}" ${state.busy ? 'disabled' : ''}>${t}</button>`).join('')}</div><div class="dq-item-groups">${[...groups].map(([key,items]) => `<section class="dq-item-group"><header><strong>${key === 'individual' ? 'Individual orders' : `Shared delivery #${key.slice(0,8)}`}</strong><span>${items.length} item${items.length === 1 ? '' : 's'}${key === 'individual' ? '' : ' · selected together'}</span></header>${items.map(o => `<label class="dq-item ${state.selected.has(String(o.id)) ? 'selected' : ''}"><input type="checkbox" data-dq-order="${o.id}" ${state.selected.has(String(o.id)) ? 'checked' : ''} ${state.busy ? 'disabled' : ''} aria-label="Select ${safe(o.order_number)}" /><span class="dq-item-name"><strong>${safe(o.reward_name)}</strong><small><button type="button" class="dq-order-link" data-open-fulfilment-order="${o.id}">${safe(o.order_number)}</button> · ${Number(o.points_coins || o.points_cost).toLocaleString()} coins${o.trade_url_needs_review ? ' · Trade link needs review' : ''}</small></span><span class="dq-item-state"><span class="status-pill status-${safe(o.status)}">${safe(label(o.status))}</span>${o.status === 'trade_locked' ? `<small>${o.trade_locked_until ? (ready(o) ? 'Lock ended' : safe(formatTradeLockRemaining(o.trade_locked_until))) : 'Unlock time missing'}</small>` : ''}</span></label>`).join('')}</section>`).join('')}</div><div id="deliverySelectionTools" class="dq-selection"></div>`;
    renderSelection();
  }
  function renderSelection() {
    const root = $('#deliverySelectionTools'), items = chosen(); if (!root) return;
    $$('[data-dq-order]').forEach(input => { input.checked = state.selected.has(input.dataset.dqOrder); input.closest('.dq-item').classList.toggle('selected',input.checked); });
    if (!items.length) { root.innerHTML = '<p>Select the items you want to handle together. Up to 100 orders per action.</p>'; return; }
    const allUnsent = items.every(o => o.status !== 'trade_sent'), allSent = items.every(o => o.status === 'trade_sent');
    const sendable = allUnsent && items.every(ready), stale = items.some(o => o.trade_url_needs_review);
    const url = items[0].steam_trade_url, sameUrl = items.every(o => o.steam_trade_url === url), safeUrl = sameUrl && validTrade(url);
    const oneShared = items[0].delivery_id && items.every(o => o.delivery_id === items[0].delivery_id);
    const early = items.filter(purchase).length, toReady = items.filter(o => ready(o) && o.status !== 'ready_to_trade').length;
    const toOrder = items.filter(o => purchase(o) && o.status !== 'ordered').length;
    const qty = new Map(); for (const o of items) qty.set(o.reward_name,(qty.get(o.reward_name) || 0)+1);
    const defaultUntil = new Date(Date.now()+192*3600000); const localUntil = new Date(defaultUntil.getTime()-defaultUntil.getTimezoneOffset()*60000).toISOString().slice(0,16);
    root.innerHTML = `<div class="dq-selection-head"><h3>${items.length} selected item${items.length === 1 ? '' : 's'}</h3><div class="dq-selection-actions">${allUnsent && items.length > 1 && !oneShared ? '<button type="button" class="admin-secondary-button" data-dq-group>Make shared delivery</button>' : ''}${allUnsent && items.some(o => o.delivery_id) ? '<button type="button" class="admin-text-button" data-dq-split>Separate orders</button>' : ''}</div></div><div class="dq-pick-list"><strong>Items to include in Steam</strong>${[...qty].map(([name,count]) => `<span><b>${count} ×</b> ${safe(name)}</span>`).join('')}</div>${stale ? `<aside class="dq-review"><strong>Review the customer's updated trade link</strong><code>${safe(items[0].current_trade_url || 'Missing trade link')}</code><button type="button" class="admin-secondary-button" data-dq-review ${validTrade(items[0].current_trade_url) && allUnsent ? '' : 'disabled'}>I checked the account — use this link</button></aside>` : ''}${sameUrl ? `<div class="dq-steam-tools"><label>Steam message<textarea id="deliverySteamMessage" readonly rows="2">${safe(offerMessage(items))}</textarea></label><div><button type="button" class="admin-secondary-button" data-dq-copy="message">Copy message</button><button type="button" class="admin-secondary-button" data-dq-copy="url" ${safeUrl ? '' : 'disabled'}>Copy trade link</button>${safeUrl && !stale && allUnsent && sendable ? `<a class="admin-primary-button" href="${safe(url)}" target="_blank" rel="noopener noreferrer">Open Steam trade ↗</a>` : ''}</div><small>${allSent ? 'Saved address for the sent offer.' : 'Check the account and add every item above before sending.'}</small></div>` : '<p class="dq-warning">The selected orders have different saved trade links. Review the current link before sending.</p>'}<div class="dq-bulk-actions">${toOrder ? `<button type="button" class="admin-secondary-button" data-dq-action="ordered">Awaiting purchase (${toOrder})</button>` : ''}${toReady ? `<button type="button" class="admin-secondary-button" data-dq-action="ready_to_trade">Items ready (${toReady})</button>` : ''}${sendable ? `<label>Sent offer URL (optional)<input id="deliverySentOffer" placeholder="https://steamcommunity.com/tradeoffer/123456789/" maxlength="500" /></label><button type="button" class="admin-primary-button" data-dq-action="trade_sent" ${stale || !safeUrl ? 'disabled' : ''}>I sent the Steam offer (${items.length})</button>` : ''}${allSent ? `<button type="button" class="admin-primary-button" data-dq-action="completed">Customer accepted — complete (${items.length})</button>` : ''}${early ? `<div class="dq-purchase-action"><label>Purchased items: actual Steam unlock time<input id="deliveryPurchasedUntil" type="datetime-local" value="${localUntil}" required /></label><button type="button" class="admin-primary-button" data-dq-action="trade_locked">Purchased / trade locked (${early})</button><small>Only ${early} item${early === 1 ? '' : 's'} awaiting purchase will change. Existing locks and ready items keep their stage.</small></div>` : ''}</div>${!sendable && !allSent ? '<p class="dq-help">To send an offer now, select Ready now. Purchased items remain here until their Steam locks end.</p>' : ''}`;
    if (state.busy) $$('button,input',root).forEach(x => x.disabled = true);
  }
  async function mutate(kind,button) {
    if (state.busy || state.loading) return;
    const items = chosen(); if (!items.length || items.length > 100) return message('Select 1–100 items.','error');
    const p_order_ids = items.map(o => Number(o.id)), p_expected = expected(items), c = current();
    let args = {p_order_ids,p_expected}, name, action = button.dataset.dqAction;
    if (kind === 'action') {
      name = 'sq_admin_fulfil_orders'; args.p_action = action;
      args.p_lock_until = null; args.p_trade_offer_url = null;
      if (action === 'trade_locked') {
        const value = $('#deliveryPurchasedUntil')?.value;
        if (!value || Number.isNaN(new Date(value).getTime()) || new Date(value) <= new Date()) return message('Enter the future unlock time shown in Steam.','error');
        args.p_lock_until = new Date(value).toISOString();
      }
      if (action === 'trade_sent') {
        const offer = $('#deliverySentOffer')?.value.trim();
        if (offer && !isValidSteamTradeOfferUrl(offer)) return message('Enter a valid Steam offer URL.','error');
        args.p_trade_offer_url = offer || null;
      }
    } else if (kind === 'review') { name = 'sq_admin_review_order_trade_urls'; args.p_expected_url = items[0].current_trade_url; }
    else { name = 'sq_admin_set_delivery'; args.p_split = kind === 'split'; }
    const beforeConfirm = state.seq;
    if (action === 'trade_sent' || action === 'completed' || kind === 'review') {
      const text = kind === 'review' ? `Confirm you checked the Steam account for ${c.name}. Use the current link on these ${items.length} unsent orders?`
        : action === 'completed' ? `Confirm ${c.name} accepted the Steam offer(s) containing these ${items.length} items. This completes their orders.`
        : `Confirm you sent ONE Steam offer to ${c.name} containing all ${items.length} selected item${items.length === 1 ? '' : 's'}. ${items.length > 1 ? 'These items will be recorded as one shared delivery.' : ''}`;
      if (!await showConfirm(text,{title:kind === 'review' ? 'Review trade link' : action === 'completed' ? 'Offer accepted?' : 'Offer sent?',confirmText:kind === 'review' ? 'Use checked link' : action === 'completed' ? 'Complete orders' : 'Record sent offer'})) return;
    }
    if (beforeConfirm !== state.seq || c.user_id !== state.current || JSON.stringify(p_order_ids) !== JSON.stringify(chosen().map(o => Number(o.id)))) return message('The selection changed. Check it again.','info');
    state.busy = true; render();
    try {
      const data = await rpc(name,args);
      message(kind === 'group' ? 'Shared delivery created.' : kind === 'split' ? 'Orders separated.' : kind === 'review' ? 'Trade link reviewed.' : `${data.count} order${Number(data.count) === 1 ? '' : 's'} updated${data.skipped ? ` · ${data.skipped} already at another stage` : ''}.`,'success');
      if (kind === 'action') {
        const notifyOrders = items.filter(o => data.changed_ids?.includes(Number(o.id)));
        const groups = new Set();
        for (const o of notifyOrders) {
          const key = data.delivery_id || o.delivery_id || String(o.id); if (groups.has(key)) continue; groups.add(key);
          const pending = sb.functions.invoke('reward-order-status-notify',{body:{request_id:o.id}});
          pending.then(({error}) => {if(error) message('Orders saved; customer email needs a retry from Reward orders.','info');}).catch(() => message('Orders saved; customer email needs a retry from Reward orders.','info'));
        }
      }
      await load(false,true);
    } catch (e) { message(e.message,'error'); await load(false,true); }
    finally { state.busy = false; render(); }
  }
  function bind() {
    if (state.bound || !$('#adminDeliveries')) return; state.bound = true;
    $('#deliveryQueueSearch').addEventListener('input',e => { clearTimeout(state.timer); state.search = e.target.value.trim(); state.seq++; state.loading = true; state.timer = setTimeout(() => load(false,false),250); });
    document.addEventListener('click',e => {
      const b = e.target.closest('button'); if(!b) return;
      if (b.matches('[data-dq-refresh]')) { clearTimeout(state.timer); if(!state.busy) load(); }
      if (state.busy) return;
      if (b.matches('[data-dq-filter]')) { state.filter = b.dataset.dqFilter; $$('[data-dq-filter]').forEach(x => {x.classList.toggle('active',x.dataset.dqFilter === state.filter); x.setAttribute('aria-pressed',String(x.dataset.dqFilter === state.filter));}); load(false,false); }
      if (b.matches('[data-dq-more]')) load(true);
      if (b.matches('[data-dq-customer]') && !state.loading) { chooseCustomer(b.dataset.dqCustomer); render(); }
      if (b.matches('[data-dq-nav]') && !state.loading) { const index = state.customers.findIndex(c => c.user_id === state.current)+Number(b.dataset.dqNav); if(state.customers[index]) {chooseCustomer(state.customers[index].user_id);render();} }
      if (b.matches('[data-dq-select]') && !state.loading) { const kind = b.dataset.dqSelect; selectItems(o => kind === 'ready' ? ready(o) && !o.trade_url_needs_review : kind === 'purchase' ? purchase(o) : kind === 'sent' ? o.status === 'trade_sent' : kind === 'unsent' ? o.status !== 'trade_sent' : false);renderSelection(); }
      if (b.matches('[data-dq-action]')) mutate('action',b);
      if (b.matches('[data-dq-group]')) mutate('group',b);
      if (b.matches('[data-dq-split]')) mutate('split',b);
      if (b.matches('[data-dq-review]')) mutate('review',b);
      if (b.matches('[data-dq-copy]')) {
        const value = b.dataset.dqCopy === 'message' ? $('#deliverySteamMessage')?.value : chosen()[0]?.steam_trade_url;
        if(value) navigator.clipboard.writeText(value).then(() => message('Copied.','success')).catch(() => {const field = $('#deliverySteamMessage'); if(b.dataset.dqCopy === 'message') {field?.focus();field?.select();message('Message selected — press Ctrl+C.','info');} else message('Clipboard unavailable. Open the order to copy the link.','info');});
      }
    });
    document.addEventListener('change',e => {
      if (!e.target.matches('[data-dq-order]') || state.busy || state.loading) return;
      const o = current()?.items.find(x => String(x.id) === e.target.dataset.dqOrder); if(!o) return;
      const members = o.delivery_id ? current().items.filter(x => x.delivery_id === o.delivery_id) : [o];
      if (e.target.checked && new Set([...state.selected,...members.map(x => String(x.id))]).size > 100) {e.target.checked = false;return message('Up to 100 orders per action.','info');}
      members.forEach(x => e.target.checked ? state.selected.add(String(x.id)) : state.selected.delete(String(x.id))); renderSelection();
    });
  }
  window.SQDeliveries = {load,prepare:bind};
})();
