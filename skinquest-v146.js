/* SkinQuest v15.0.3: fixed reward journeys, private order pages and linked support. */
(() => {
  "use strict";
  const $ = (s, root=document) => root.querySelector(s);
  const $$ = (s, root=document) => Array.from(root.querySelectorAll(s));
  const safe = v => String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#039;");
  const n = v => Number(v||0).toLocaleString();
  const date = v => v ? new Date(v).toLocaleString([], {dateStyle:"medium",timeStyle:"short"}) : "Not recorded";
  const id = v => /^[1-9][0-9]{0,15}$/.test(String(v||"")) ? String(v) : null;
  const params = () => new URLSearchParams(location.search);
  const routeId = kind => id(location.pathname.match(new RegExp(`^/${kind}/([0-9]+)/?$`))?.[1] || params().get("id"));
  const errorBox = (title,copy,retry="") => `<div class="sq146-empty"><h2>${safe(title)}</h2><p class="muted">${safe(copy)}</p>${retry?`<button class="button button-ghost" type="button" data-sq146-retry="${retry}">Try again</button>`:""}</div>`;
  let prepared=false, detailSeq=0, supportSeq=0, starterSeq=0, suggestionSeq=0, suggestionTimer;
  let detail=null, selected=null, supportKey=null;
  const ledger={uid:null,items:[],total:0,kind:"all",seq:0,loading:false,expanded:false};
  let extra={weapon:'all',condition:'all',rarity:'all'};
  const resetExtraQuery=()=>{extra={weapon:'all',condition:'all',rarity:'all'};};
  const extraQuery=()=>Object.values(extra).filter(v=>v&&v!=='all').map(v=>v==='mil-spec'?'milspec':v).join(' ');
  async function extraFilters(values){extra={...values};try{await loadRewards();window.__skinquestRewardApply?.(true);}catch(e){showMessage(e.message||'Could not apply catalogue filters.','error');}}
  async function rpc(name,args={}) {
    const {data,error}=await withTimeout(sb.rpc(name,args),25000,"The connection timed out. Check the page before retrying a submitted request.");
    if(error)throw error;return data;
  }
  function accountGate(root) {
    root.innerHTML=`<section class="panel sq146-empty"><span class="pill">Private account page</span><h2>Sign in to continue</h2><p class="muted">Orders, transactions and support requests are only visible on your own account.</p><button class="button button-primary" type="button" data-sq146-login>Sign in</button></section>`;
  }
  function action(item) {
    const a=getRewardActionState(item,currentProfile);
    return `<button class="button button-primary" type="button" data-detail-action="${safe(a.action)}" ${a.disabled?"disabled":""}>${safe(a.label)}</button>${['email','trade','out','price','login'].includes(a.action)?`<p class="muted sq146-action-note">${safe(a.note)}</p>`:''}`;
  }
  function miniReward(item) {
    const missing=Math.max(0,getRewardCost(item)-Number(currentProfile?.points_balance||0));
    return `<a class="sq146-starter-card" href="/rewards/${item.id}">${renderRewardArt(item)}<div><h3>${safe(item.family_name||item.name)}</h3><strong>${n(getRewardCost(item))} coins</strong><span>${getRewardAvailableStock(item)>0?`${n(getRewardAvailableStock(item))} in stock`:`Available to order · at least ${getRewardOrderEtaDays(item)} days`}</span>${currentUser?`<small>${missing?`${n(missing)} coins to go`:"Within your balance · check delivery setup"}</small>`:""}</div></a>`;
  }
  async function starters() {
    const target=$("#firstRewardListings");if(!target)return;
    const seq=++starterSeq;
    try {
      const data=await rpc("sq_browse_reward_families",{p_sort:"price-asc",p_show_out_of_stock:false,p_limit:12,p_offset:0});
      if(seq!==starterSeq)return;
      const items=(data?.items||[]).filter(r=>rewardHasCurrentPrice(r)&&!rewardIsOutOfStock(r)).slice(0,6);
      target.innerHTML=items.length?items.map(miniReward).join(""):errorBox("The first rewards are being prepared","Check the catalogue again later. We will not show unavailable rewards as ready to claim.");
    } catch(e) {if(seq===starterSeq)target.innerHTML=errorBox("Could not load current rewards","Please try again. Reward prices and stock must be loaded before we can recommend an item.","starters");}
  }
  async function rewardDetail() {
    const root=$("#rewardDetail");if(!root)return;
    const rewardId=routeId("rewards"),seq=++detailSeq;
    if(!rewardId){root.innerHTML=errorBox("Reward not found","Choose an item from the reward catalogue.");return;}
    try {
      const result=await rpc("sq_reward_details",{p_reward_id:rewardId});
      if(seq!==detailSeq)return;
      if(!result?.variants?.length){root.innerHTML=errorBox("This reward is not available","The listing may be hidden or removed. Existing orders keep their saved item name and coin price.");return;}
      detail=result;selected=result.variants.find(r=>String(r.id)===rewardId)||result.variants[0];
      rewardItems=result.variants;await loadFavoriteRewards(currentUser?.id);
      if(seq!==detailSeq)return;
      renderDetail();
    } catch(e){if(seq===detailSeq)root.innerHTML=errorBox("Could not load this reward",e.message||"Please try again.","reward");}
  }
  const types=[['normal','Normal'],['souvenir','Souvenir'],['stattrak','StatTrak™']];
  const wears=[['FN','Factory New'],['MW','Minimal Wear'],['FT','Field-Tested'],['WW','Well-Worn'],['BS','Battle-Scarred']];
  function variantType(v) {
    const names=[v.market_name,v.name].filter(Boolean);
    if(names.some(name=>/^souvenir\s+/i.test(name)))return 'souvenir';
    if(names.some(name=>/^stattrak(?:™|\s|$)/i.test(name)))return 'stattrak';
    return 'normal';
  }
  function variantWear(v) {
    const code=String(v.condition||'').trim().toUpperCase();
    if(wears.some(([c])=>c===code))return code;
    const name=[v.condition,v.market_name,v.name].filter(Boolean).join(' ');
    return wears.find(([,label])=>name.toLowerCase().includes(label.toLowerCase()))?.[0]||'STD';
  }
  function sortedVariants(kind) {
    const rank=v=>{const i=wears.findIndex(([c])=>c===variantWear(v));return i<0?5:i;};
    return detail.variants.filter(v=>variantType(v)===kind).sort((a,b)=>rank(a)-rank(b)||getRewardCost(a)-getRewardCost(b)||Number(a.id)-Number(b.id));
  }
  function renderVariantPicker() {
    if(detail.variants.length<2)return '';
    const kind=variantType(selected),available=types.filter(([k])=>detail.variants.some(v=>variantType(v)===k));
    return `<section class="sq146-variant-picker"><h2>Choose condition</h2>
      <div class="sq146-type-tabs ${available.length===1?'single-type':''}" role="tablist" aria-label="Item type">${available.map(([k,label])=>`<button id="variant-tab-${k}" class="sq146-type-tab is-${k} ${k===kind?'is-active':''}" type="button" role="tab" aria-selected="${k===kind}" aria-controls="variant-wear-panel" tabindex="${k===kind?0:-1}" data-variant-type="${k}">${label}</button>`).join('')}</div>
      <div id="variant-wear-panel" class="sq146-variant-list" role="tabpanel" aria-labelledby="variant-tab-${kind}">${sortedVariants(kind).map(v=>{const code=variantWear(v),label=wears.find(([c])=>c===code)?.[1]||'Standard';return `<button class="sq146-variant is-${kind} ${v.id===selected.id?'is-selected':''}" type="button" data-variant-id="${v.id}" aria-pressed="${v.id===selected.id}"><span class="sq146-wear-badge wear-${code.toLowerCase()}">${code==='STD'?'—':code}</span><span class="sq146-wear-copy"><strong>${label}</strong><small>${!rewardHasCurrentPrice(v)?'Price updating':rewardIsOutOfStock(v)?'Out of stock':getRewardAvailableStock(v)>0?`${n(getRewardAvailableStock(v))} in stock`:'Available to order'}</small></span><span class="sq146-wear-price">${v.id===selected.id?'Selected':`${n(getRewardCost(v))}<small>coins</small>`}</span><span class="sq146-wear-check" aria-hidden="true">${v.id===selected.id?'✓':''}</span></button>`;}).join('')}</div></section>`;
  }
  function selectVariant(v) {
    if(!v)return;selected=v;history.replaceState(null,'',`/rewards/${v.id}`);renderDetail();
  }
  function renderDetail() {
    const root=$("#rewardDetail"),item=selected;if(!root||!item)return;
    const url=`${location.origin}/rewards/${item.id}`;
    document.title=`${item.name} — SkinQuest reward`;
    let canonical=$('link[rel="canonical"]');if(!canonical){canonical=document.createElement("link");canonical.rel="canonical";document.head.append(canonical);}canonical.href=url;
    const description=$('meta[name="description"]');if(description)description.content=`${item.name}: ${n(getRewardCost(item))} SkinQuest coins. Check the exact variant, stock and Steam delivery details.`;
    const available=getRewardAvailableStock(item),orderable=rewardIsOrderable(item),starred=favoriteRewardIds.has(Number(item.id));
    const balance=Number(currentProfile?.points_balance||0),missing=Math.max(0,getRewardCost(item)-balance),pct=Math.min(100,Math.max(0,balance/getRewardCost(item)*100));
    const family=item.family_name||item.name;
    root.innerHTML=`<section class="sq146-detail-layout">
      <div class="sq146-detail-aside">
        <div class="panel sq146-detail-art">${renderRewardArt(item)}</div>
        <details class="panel sq146-delivery-info"><summary>How delivery works</summary><p>Coins are deducted only when the server saves your order. Each order keeps its original item and coin price.</p><p>${orderable?`SkinQuest purchases the item after review. Allow at least ${getRewardOrderEtaDays(item)} days; the actual recorded Steam unlock time is shown on your private order page. This is not a guaranteed delivery date.`:'Prepared items are usually sent within 1–2 days after review. Delivery is manual, not instant.'}</p><a class="mini-link" href="/orders">My orders</a> · <a class="mini-link" href="/how-it-works">Delivery guide</a></details>
      </div>
      <div class="panel sq146-detail-copy"><div class="sq146-detail-badges">${variantWear(item)!=='STD'||variantType(item)!=='normal'?`<span class="sq146-type-badge is-${variantType(item)}">${types.find(([k])=>k===variantType(item))[1]}</span>`:''}<span class="stock-pill">${orderable?'Available to order':available>0?`${n(available)} in stock`:'Out of stock'}</span></div><h1>${safe(family)}</h1>
      ${item.name!==family?`<p class="muted sq151-selected-name">${safe(item.name)}</p>`:''}
      <strong class="sq146-detail-price">${n(getRewardCost(item))}<small> coins</small></strong>
      <p class="muted sq151-price-caption">${rewardHasCurrentPrice(item)?'Price saved at checkout':'Price refreshing · ordering paused'}</p>
      ${renderVariantPicker()}
      ${currentUser?`<div class="sq146-goal-progress"><p>${missing?(balance>0?`${n(missing)} coins to go`:'Start earning toward this reward'):'Within your balance'}<small>${Math.round(pct)}% saved</small></p><div class="goal-progress-bar" role="progressbar" aria-label="Reward goal progress" aria-valuenow="${Math.round(pct)}" aria-valuemin="0" aria-valuemax="100"><span style="width:${pct}%"></span></div></div>`:''}
      <div class="sq151-delivery-summary"><strong>${orderable?`Purchase required · ${getRewardOrderEtaDays(item)}+ days`:'Prepared stock · usually 1–2 days'}</strong><p>${orderable?'Purchased after review. The recorded Steam unlock time appears on your order.':'Reserved when your order is saved, then reviewed before sending.'} Delivery is manual; timing is an estimate.</p></div>
      <div class="sq146-detail-actions">${action(item)}<button class="button button-ghost" type="button" data-detail-star aria-pressed="${starred}">${starred?'★ Reward saved':'☆ Save reward'}</button><button class="button button-ghost" type="button" data-copy-reward-link>Copy link</button></div>
      <p class="muted sq146-security-copy">Never share your Steam password, Guard codes or API key.</p></div>
      </section>`;
  }
  const statusCopy={
    pending:["Waiting for review","Your request is saved. SkinQuest will review the request before fulfilment."],
    reviewing:["Under review","SkinQuest is checking the request. No further action is required unless support contacts you."],
    ordered:["Awaiting purchase","The order is accepted for purchasing. The exact Steam trade-lock time is not confirmed until it is recorded after purchase."],
    trade_locked:["Steam trade lock","The purchased item is not tradable yet. The countdown is to the unlock time, not a promise that the trade will be sent immediately."],
    ready_to_trade:["Queued for delivery","The item is ready for SkinQuest to send. A trade is not considered sent until its status is updated."],
    trade_sent:["Check your Steam offers","SkinQuest has marked the offer as sent. Check the item against this order before accepting it."],
    completed:["Order completed","SkinQuest has recorded this delivery as completed."],
    rejected:["Order rejected","The order is closed. Any returned coins are recorded separately in Coin history."],
    refunded:["Order refunded","The order is closed. Check Coin history for the exact refund entry."],
    cancelled:["Order cancelled","The order is closed. Check Coin history for any recorded refund."]
  };
  async function orderDetail() {
    const root=$("#orderDetail");if(!root)return;
    const seq=++detailSeq,user=currentUser||await getSessionUser();
    if(seq!==detailSeq)return;if(!user){accountGate(root);return;}
    const orderId=routeId("orders");if(!orderId){root.innerHTML=errorBox("Order not found","Choose an order from your dashboard.");return;}
    try {
      const item=await rpc("sq_my_order",{p_order_id:orderId});
      if(seq!==detailSeq||currentUser?.id!==user.id)return;
      if(!item){root.innerHTML=errorBox("Order not available","This order was not found on your account. Sign in with the account that placed it.");return;}
      const unlocked=item.status==="trade_locked"&&item.trade_locked_until&&new Date(item.trade_locked_until).getTime()<=Date.now();
      const copy=unlocked?["Trade lock ended","The recorded Steam lock has ended. SkinQuest still needs to send the offer; it has not been marked as sent."]:(statusCopy[item.status]||["Status recorded",String(item.status)]);
      document.title=`${item.order_number} — SkinQuest order`;
      const timeline=[["Request saved",item.created_at],["Purchase recorded",item.purchased_at],["Ready for delivery",item.ready_at],["Trade marked sent",item.trade_sent_at],["Completed",item.completed_at],["Refund recorded",item.refunded_at]].filter(x=>x[1]).sort((a,b)=>new Date(a[1])-new Date(b[1]));
      root.innerHTML=`<section class="panel sq146-order-head"><div><span class="pill">Your reward order</span><h1>${safe(item.order_number)}</h1><h2>${item.reward_id==null?"Deleted item · ":""}${safe(item.reward_name)}</h2><p class="muted">Saved price: <strong>${n(getRequestCost(item))} coins</strong> · ${item.fulfillment_mode==="orderable"?"Purchased after request":"Prepared stock"}</p></div><span class="status-pill status-${safe(item.status)}">${safe(formatStatus(item.status))}</span></section>
      <section class="panel sq146-order-state"><span class="pill">Next step</span><h2>${safe(copy[0])}</h2><p>${safe(copy[1])}</p>
      ${item.status==="trade_locked"&&item.trade_locked_until?`<div class="sq146-countdown"><strong data-sq146-countdown="${safe(item.trade_locked_until)}">${safe(formatTradeLockRemaining(item.trade_locked_until))}</strong><span>Recorded unlock: ${date(item.trade_locked_until)}</span></div>`:""}
      ${item.estimated_ready_at&&!item.trade_locked_until&&!['completed','cancelled','rejected','refunded'].includes(item.status)?`<p class="muted">Initial readiness estimate: ${date(item.estimated_ready_at)}. This may change; it is not a guaranteed delivery deadline.</p>`:""}
      ${item.status==='trade_sent'?isValidSteamTradeOfferUrl(item.trade_offer_url)?`<a class="button button-primary" href="${safe(item.trade_offer_url)}" target="_blank" rel="noopener noreferrer">Open Steam offer</a>`:`<a class="button button-primary" href="https://steamcommunity.com/my/tradeoffers/" target="_blank" rel="noopener noreferrer">Open your Steam offers</a>`:""}
      ${item.customer_note?`<div class="sq146-customer-note"><h3>Update from SkinQuest</h3><p>${safe(item.customer_note)}</p></div>`:""}</section>
      <div class="sq146-order-grid"><section class="panel"><h2>Recorded milestones</h2><ol class="sq146-milestones">${timeline.map(([label,time])=>`<li><strong>${safe(label)}</strong><time>${date(time)}</time></li>`).join("")}</ol><p class="muted">Only recorded dates are shown. Latest record update: ${date(item.updated_at)}.</p></section>
      <section class="panel"><h2>Need help with this order?</h2><p class="muted">Your order number, item and saved coin price are attached automatically. Do not send passwords, Steam Guard codes or API keys.</p><a class="button button-ghost" href="/support?order=${item.id}">Contact support about this order</a>${item.reward_id?`<a class="mini-link" href="/rewards/${item.reward_id}">View original listing</a>`:""}</section></div>`;
      window.SQ15?.augmentOrder(item);
    } catch(e){if(seq===detailSeq)root.innerHTML=errorBox("Could not load your order",e.message||"Please try again.","order");}
  }
  async function coinHistory(userId,append=false) {
    const root=$("#coinHistory");if(!root)return;
    if(ledger.uid!==userId){ledger.uid=userId;ledger.kind="all";ledger.items=[];ledger.expanded=false;}
    const seq=++ledger.seq;ledger.loading=true;
    try {
      const data=await rpc("sq_my_coin_history",{p_kind:ledger.kind,p_limit:ledger.expanded?25:3,p_offset:append?ledger.items.length:0});
      if(seq!==ledger.seq||currentUser?.id!==userId)return;
      ledger.items=append?[...ledger.items,...(data?.items||[])]:data?.items||[];ledger.total=Number(data?.total||0);
      const labels={all:"All",survey:"Surveys",earn:"Tasks",reward:"Rewards",refund:"Refunds",promo:"Promo codes",level:"Level bonuses",adjustment:"Adjustments"};
      const kinds={survey:"Survey reward",earn:"Task reward",reward:"Reward order",refund:"Coin refund",promo:"Promo code",level:"Level bonus",adjustment:"Account adjustment"};
      root.className="sq146-ledger";
      root.innerHTML=`${ledger.expanded?`<div class="sq146-chips" role="group" aria-label="Coin history type">${Object.entries(labels).map(([k,v])=>`<button class="filter-chip ${k===ledger.kind?"active":""}" type="button" data-ledger-kind="${k}" aria-pressed="${k===ledger.kind}">${v}</button>`).join("")}</div>`:""}<p class="muted sq146-ledger-caption">${ledger.items.length} of ${n(ledger.total)} transactions.</p>${ledger.items.length?ledger.items.map(c=>`<div class="sq146-ledger-row"><div><span class="sq146-ledger-kind">${safe(['survey','earn'].includes(c.kind)&&Number(c.amount)<0?'Partner reversal':kinds[c.kind]||'Account adjustment')}</span><strong>${safe(c.reason||kinds[c.kind]||'Coin adjustment')}</strong><small>${date(c.created_at)} · Transaction #${c.id}${c.provider?` · ${safe(c.provider)}`:""}</small>${c.kind==='refund'?`<small>Actual returned coins; your original order price has not changed.</small>`:['survey','earn'].includes(c.kind)&&Number(c.amount)<0?`<small>The provider reversed a previously recorded reward.</small>`:""}<div class="sq146-row-links">${c.order_id?`<a href="/orders/${c.order_id}">View order</a>`:""}<a href="/support?transaction=${c.id}">Ask about this transaction</a></div></div><strong class="sq146-amount ${Number(c.amount)>=0?'positive':'negative'}">${Number(c.amount)>0?'+':''}${n(c.amount)}<small> coins</small></strong></div>`).join(""):errorBox("No recorded movements","There are no entries in this history section. Missing records are not proof that a survey was completed.")}${ledger.items.length<ledger.total?`<button class="button button-ghost" type="button" data-ledger-more>Show more</button>`:""}${ledger.expanded?'<button class="button button-ghost" type="button" data-ledger-less>Show less</button>':""}`;
    } catch(e){if(seq===ledger.seq)root.innerHTML=errorBox("Coin history unavailable",e.message||"Try again.","ledger");}
    finally{if(seq===ledger.seq)ledger.loading=false;}
  }
  async function supportPage() {
    const root=$("#linkedSupport");if(!root)return;
    const seq=++supportSeq,user=currentUser||await getSessionUser();if(seq!==supportSeq)return;
    if(!user){accountGate(root);return;}
    if(!hasActiveContactEmail(user,currentProfile)){root.innerHTML=errorBox("Verify a contact email first","Open Settings and verify a real email address so support can reply.")+`<a class="button button-primary" href="/settings">Open Settings</a>`;return;}
    try {
      const data=await rpc('sq_my_support_context');if(seq!==supportSeq||currentUser?.id!==user.id)return;
      const wantedOrder=id(params().get('order')),wantedCoin=id(params().get('transaction'));
      let orders=data?.orders||[],coins=data?.transactions||[];
      if(wantedOrder&&!orders.some(o=>String(o.id)===wantedOrder)){const extra=await rpc('sq_my_order',{p_order_id:wantedOrder});if(extra)orders=[extra,...orders];}
      // Old transactions can still be linked by the private id; the submit RPC validates ownership.
      const coinIsOld=wantedCoin&&!coins.some(c=>String(c.id)===wantedCoin);
      const invalidOrder=wantedOrder&&!orders.some(o=>String(o.id)===wantedOrder);
      if(seq!==supportSeq||currentUser?.id!==user.id)return;
      root.innerHTML=`<div class="sq146-support-layout"><section class="panel"><h2>Contact SkinQuest</h2><p class="muted">Your verified contact email is used automatically. Support replies by email; ticket status is shown below.</p>${invalidOrder?'<p class="form-feedback form-feedback-error">That order was not found on your account. Choose one of your own orders.</p>':''}
      <form id="linkedSupportForm" class="sq146-form"><label>Topic<select name="topic">${['Reward order','Missing coins','Survey issue','Account','Other'].map(t=>`<option ${wantedOrder&&t==='Reward order'||wantedCoin&&t==='Missing coins'||params().get('topic')==='survey'&&t==='Survey issue'?'selected':''}>${t}</option>`).join('')}</select></label>
      <label>Attach an order<select name="order"><option value="">No order / account question</option>${orders.map(o=>`<option value="${o.id}" ${String(o.id)===wantedOrder?'selected':''}>${safe(o.order_number)} · ${safe(o.reward_name)} · ${n(o.points_coins)} coins</option>`).join('')}</select></label>
      <label>Attach a recorded coin transaction<select name="transaction"><option value="">No recorded transaction / missing reward</option>${coinIsOld?`<option value="${wantedCoin}" selected>Older transaction #${wantedCoin} · ownership checked when submitted</option>`:''}${coins.map(c=>`<option value="${c.id}" ${String(c.id)===wantedCoin?'selected':''}>#${c.id} · ${n(c.amount)} coins · ${safe(c.reason||'Coin movement')}</option>`).join('')}</select></label>
      <label>What happened?<textarea name="message" minlength="20" maxlength="2000" rows="6" required placeholder="Tell us what happened and when. For a missing survey reward, include the provider and survey reference if available. Never include passwords, tokens or Steam Guard codes."></textarea></label><small class="muted">20–2,000 characters. Coins cannot be credited from an unverified completion claim.</small><p id="linkedSupportFeedback" class="form-feedback" role="status" aria-live="polite"></p><button class="button button-primary" type="submit">Send support request</button></form></section>
      <section class="panel"><h2>Your recent tickets</h2><p class="muted">Up to 25 recent requests. Replies are sent to your verified email.</p>${(data?.tickets||[]).length?data.tickets.map(t=>`<div class="sq146-ticket"><strong>${safe(t.ticket_number)}</strong><span>${safe(t.topic)} · ${safe(formatStatus(t.status))}</span><small>${date(t.created_at)}${t.context_snapshot?.order_number?` · ${safe(t.context_snapshot.order_number)}`:''}</small></div>`).join(''):errorBox("No support tickets yet","Requests sent on this account will appear here.")}</section></div>`;
      $('#linkedSupportForm').addEventListener('submit',submitSupport);
      window.refreshSkinQuestSelects?.();
    }catch(e){if(seq===supportSeq)root.innerHTML=errorBox('Could not load support',e.message||'Try again.','support');}
  }
  async function submitSupport(event) {
    event.preventDefault();const form=event.currentTarget;if(form.dataset.submitting)return;
    const button=$('button[type="submit"]',form),feedback=$('#linkedSupportFeedback'),userId=currentUser?.id;
    const values=new FormData(form),payload={p_request_id:supportKey||crypto.randomUUID(),p_topic:values.get('topic'),p_message:String(values.get('message')||'').trim(),p_order_id:id(values.get('order')),p_coin_id:id(values.get('transaction'))};
    supportKey=payload.p_request_id;form.dataset.submitting='true';button.disabled=true;button.textContent='Sending…';feedback.textContent='Saving your request…';
    const fields=$$('input,select,textarea',form).map(field=>({field,disabled:field.disabled}));fields.forEach(({field})=>{field.disabled=true;});window.refreshSkinQuestSelects?.();
    try{
      const result=await rpc('sq_submit_linked_support',payload);if(!result?.ok)throw Error('No support request was confirmed.');
      if(currentUser?.id!==userId)return;
      feedback.textContent=`Saved as ${result.ticket_number}. Support will reply to your verified contact email.`;feedback.className='form-feedback form-feedback-success';
      form.reset();supportKey=null;button.textContent='Request sent';
    }catch(e){if(currentUser?.id!==userId)return;feedback.textContent=e.message||'Could not submit. Retrying this unchanged form uses the same request identifier.';feedback.className='form-feedback form-feedback-error';button.disabled=false;button.textContent='Retry request';}
    finally{fields.forEach(({field,disabled})=>{field.disabled=disabled;});window.refreshSkinQuestSelects?.();delete form.dataset.submitting;}
  }
  function prepare() {
    if(prepared)return;prepared=true;
    const legacyReward=id(params().get('reward'));
    if($('#rewardsGrid')&&legacyReward){location.replace(`/rewards/${legacyReward}`);return;}
    const search=$('#skinSearch'),suggestions=$('#rewardSearchSuggestions');
    if(search)search.placeholder='Search rewards…';
    const closeSuggestions=()=>{suggestions?.classList.add('hidden');search?.setAttribute('aria-expanded','false');};
    if(search&&suggestions){
      search.addEventListener('input',()=>{
        const seq=++suggestionSeq,query=search.value.trim();window.clearTimeout(suggestionTimer);closeSuggestions();
        if(query.length<2)return;
        suggestionTimer=window.setTimeout(async()=>{
          try{const data=await rpc('sq_browse_reward_families',{p_query:query,p_sort:'price-asc',p_limit:5});if(seq!==suggestionSeq||document.activeElement!==search)return;
            suggestions.innerHTML=(data?.items||[]).map(r=>`<button class="sq146-suggestion" type="button" role="option" data-suggestion-id="${r.id}"><strong>${safe(r.family_name||r.name)}</strong><small>${n(getRewardCost(r))} coins${!rewardHasCurrentPrice(r)?' · Price updating':''}</small></button>`).join('');
            if(data?.items?.length){suggestions.classList.remove('hidden');search.setAttribute('aria-expanded','true');}
          }catch{closeSuggestions();}
        },220);
      });
      search.addEventListener('keydown',e=>{if(e.key==='ArrowDown'&&!suggestions.classList.contains('hidden')){e.preventDefault();$('button',suggestions)?.focus();}if(e.key==='Escape')closeSuggestions();});
      suggestions.addEventListener('click',e=>{const b=e.target.closest('[data-suggestion-id]');if(b)location.href=`/rewards/${b.dataset.suggestionId}`;});
      suggestions.addEventListener('keydown',e=>{const choices=$$('button',suggestions),i=choices.indexOf(document.activeElement);if(e.key==='Escape'){closeSuggestions();search.focus();}if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();if(e.key==='ArrowUp'&&i===0)search.focus();else choices[Math.max(0,Math.min(choices.length-1,i+(e.key==='ArrowDown'?1:-1)))]?.focus();}});
      document.addEventListener('click',e=>{if(e.target!==search&&!suggestions.contains(e.target))closeSuggestions();});
      if(params().get('starter')==='1'){setActiveRewardSort('starter');}
    }
    document.addEventListener('click',async e=>{
      if(e.target.closest('[data-sq146-login]'))return openAuthModal('login');
      const retry=e.target.closest('[data-sq146-retry]');if(retry){const f={starters,reward:rewardDetail,order:orderDetail,ledger:()=>coinHistory(currentUser?.id),support:supportPage}[retry.dataset.sq146Retry];if(f)await f();return;}
      const type=e.target.closest('[data-variant-type]');if(type&&detail){const rows=sortedVariants(type.dataset.variantType),wear=variantWear(selected);selectVariant(rows.find(v=>variantWear(v)===wear)||rows[0]);$(`[data-variant-type="${type.dataset.variantType}"]`)?.focus({preventScroll:true});return;}
      const variant=e.target.closest('[data-variant-id]');if(variant&&detail){selectVariant(detail.variants.find(v=>String(v.id)===variant.dataset.variantId));$(`[data-variant-id="${variant.dataset.variantId}"]`)?.focus({preventScroll:true});return;}
      const a=e.target.closest('[data-detail-action]');if(a&&selected){switch(a.dataset.detailAction){case'login':return openAuthModal('signup');case'email':return showSteamEmailPrompt(currentUser,currentProfile);case'trade':location.href='/settings#tradeForm';return;case'earn':location.href='/surveys';return;case'redeem':return requestRedeem(Number(selected.id),a);default:return;}}
      const star=e.target.closest('[data-detail-star]');if(star&&selected){await toggleFavoriteReward(selected.id,star);renderDetail();return;}
      if(e.target.closest('[data-copy-reward-link]')){try{await navigator.clipboard.writeText(`${location.origin}/rewards/${selected.id}`);showMessage('Reward link copied.','success');}catch{showMessage('Copy the page address from your browser.','info');}return;}
      const kind=e.target.closest('[data-ledger-kind]');if(kind){ledger.kind=kind.dataset.ledgerKind;return coinHistory(currentUser?.id);}
      const more=e.target.closest('[data-ledger-more]');if(more&&!ledger.loading){more.disabled=true;ledger.expanded=true;return coinHistory(currentUser?.id,true);}
      const less=e.target.closest('[data-ledger-less]');if(less&&!ledger.loading){less.disabled=true;ledger.expanded=false;ledger.kind='all';return coinHistory(currentUser?.id);}
      const quick=e.target.closest('[data-reward-quick]');if(quick){if(quick.dataset.rewardQuick==='starter'){setActiveRewardSort('starter');setActiveAvailabilityFilter('all');clearRewardFilterControls();}else if(quick.dataset.rewardQuick==='affordable'){setActiveAvailabilityFilter('affordable');}else{const input=$('#skinSearch');if(input)input.value=quick.dataset.rewardQuick;}try{await loadRewards();window.__skinquestRewardApply?.(true);}catch(err){showMessage(err.message||'Could not load the current catalogue.','error');}}
    });
    window.setInterval(()=>{ $$('[data-sq146-countdown]').forEach(t=>{t.textContent=formatTradeLockRemaining(t.dataset.sq146Countdown);});},30000);
    // Changing form contents after an unsuccessful request is a new request, not a replay.
    const newSupportDraft=e=>{if(e.target.closest('#linkedSupportForm')&&!$('#linkedSupportForm')?.dataset.submitting){supportKey=null;const button=$('#linkedSupportForm button[type="submit"]');if(button){button.disabled=false;button.textContent='Send support request';}}};
    document.addEventListener('input',newSupportDraft);document.addEventListener('change',newSupportDraft);
    document.addEventListener('keydown',e=>{if(!e.target.closest('[data-variant-type]')||!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;e.preventDefault();const tabs=$$('[data-variant-type]'),i=tabs.indexOf(e.target.closest('[data-variant-type]'));const next=e.key==='Home'?0:e.key==='End'?tabs.length-1:(i+(e.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length;tabs[next]?.click();});
  }
  async function init() {
    prepare();const tasks=[];
    if($('#firstRewardListings'))tasks.push(starters());
    if($('#rewardDetail'))tasks.push(rewardDetail());
    if($('#orderDetail'))tasks.push(orderDetail());
    if($('#linkedSupport'))tasks.push(supportPage());
    await Promise.allSettled(tasks);
  }
  window.SQ146={prepare,init,coinHistory,extraQuery,extraFilters,resetExtraQuery,variantType};
})();
