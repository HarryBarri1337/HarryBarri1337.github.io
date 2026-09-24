/* SkinQuest v15.1.1: giveaway display and admin controls; eligibility lives in SQL. */
(() => {
  'use strict';
  const $ = (selector, root=document) => root.querySelector(selector);
  const safe = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const date = value => new Date(value).toLocaleString([], {dateStyle:'medium',timeStyle:'short'});
  const local = value => { const d=new Date(value); return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16); };
  const image = value => {
    try {
      const u=new URL(value,location.origin);
      return (u.protocol==='https:' || (u.origin===location.origin && u.protocol==='http:')) ? safe(u.href) : '';
    } catch { return ''; }
  };
  const rpc = async (name,args={}) => {const {data,error}=await sb.rpc(name,args);if(error)throw error;return data;};
  const notify = (msg,kind='info') => showMessage(msg,kind);
  let request=0,adminRequest=0,searchRequest=0,selected=null,eventsBound=false;
  const remaining = value => {
    const ms=new Date(value).getTime()-Date.now();
    if(ms<=0)return 'Ended · awaiting the draw';
    const days=Math.floor(ms/86400000),hours=Math.ceil((ms%86400000)/3600000);
    return days ? `${days}d ${hours}h left` : `${Math.max(1,Math.ceil(ms/3600000))}h left`;
  };
  async function feed() {
    const root=$('#giveawaysGrid');if(!root)return;
    const seq=++request;
    root.setAttribute('aria-busy','true');
    root.innerHTML='<div class="sq-giveaway-empty">Loading giveaways…</div>';
    try {
      const data=await rpc('sq_giveaway_feed');
      if(!data||!Array.isArray(data.active)||!Array.isArray(data.recent))throw new Error('The giveaway feed returned an invalid response.');
      const rows=data.active,recent=data.recent;
      if(seq!==request)return;
      $('.sq-giveaway-guide')?.classList.toggle('hidden',rows.length===0);
      $('.sq-giveaway-results')?.classList.toggle('hidden',recent.length===0);
      $('.sq-giveaway-fine')?.classList.toggle('hidden',rows.length===0&&recent.length===0);
      const intro=$('#giveawayIntro');
      if(intro)intro.textContent=rows.length?'Complete a verified survey after a giveaway opens, then choose the prize you want to enter. No coins are spent.':'New prizes and their entry details will appear here when a giveaway opens.';
      root.innerHTML=rows.length?rows.map(g=>`<article class="sq-giveaway-card">
        <div class="sq-giveaway-art">${image(g.reward_image)?`<img src="${image(g.reward_image)}" alt="" loading="lazy">`:'<span aria-hidden="true">SQ</span>'}</div>
        <div class="sq-giveaway-content"><span class="sq-giveaway-kicker">SkinQuest giveaway</span><h2>${safe(g.reward_name)}</h2>
        <div class="sq-giveaway-meta"><span>${safe(remaining(g.ends_at))}</span><span>${Number(g.entry_count).toLocaleString()} entered</span></div>
        <p>Ends ${safe(date(g.ends_at))}. Earn one verified survey reward after this giveaway opens, then enter below. One qualifying reward can unlock other giveaways that were already open.</p>
        ${g.entered?(g.eligible?'<strong class="sq-giveaway-confirmed">You are entered ✓</strong>':'<div class="sq-giveaway-actions"><span>Your entry is recorded, but its survey credit is no longer verified. Earn another survey reward before the deadline to stay eligible.</span><a class="button button-ghost" href="/surveys">Go to surveys</a></div>'):
          g.eligible?`<button class="button button-primary" type="button" data-giveaway-enter="${safe(g.id)}">Enter giveaway</button>`:
          `<div class="sq-giveaway-actions"><span>${currentUser?.id?'Complete a survey to unlock entry.':'Sign in to check your eligibility.'}</span><a class="button button-ghost" href="/surveys">Go to surveys</a>${!currentUser?.id?'<button class="button button-ghost" type="button" data-giveaway-login>Sign in</button>':''}</div>`}
        </div></article>`).join(''):'<div class="sq-giveaway-empty"><span class="sq-giveaway-empty-icon" aria-hidden="true">✦</span><strong>No giveaways available right now</strong><p>When a new prize is added, you can complete a survey and enter here.</p></div>';
      const results=$('#giveawayResults');
      if(results)results.innerHTML=recent.length?recent.map(g=>`<article class="sq-giveaway-result"><div><strong>${safe(g.reward_name)}</strong><small>Ended ${safe(date(g.ends_at))} · ${Number(g.entry_count).toLocaleString()} entered</small></div><span>${g.state==='awaiting_draw'?'Draw pending':g.state==='closed'?'No valid entries':g.state==='cancelled'?'Cancelled':g.won?'You won!':'Winner selected'}</span>${g.won?'<a href="/support">Contact support about your prize →</a>':''}</article>`).join(''):'<p class="muted">Past giveaways will appear here.</p>';
    } catch(e) {
      if(seq!==request)return;
      console.error('Giveaway feed:',e);
      $('.sq-giveaway-guide')?.classList.add('hidden');
      $('.sq-giveaway-results')?.classList.add('hidden');
      $('.sq-giveaway-fine')?.classList.add('hidden');
      root.innerHTML='<div class="sq-giveaway-empty"><strong>Giveaways are temporarily unavailable</strong><p>We could not check the prizes right now. Please try again.</p><button class="button button-ghost" type="button" data-giveaway-refresh>Try again</button></div>';
    } finally {if(seq===request)root.removeAttribute('aria-busy');}
  }
  async function enter(id,button) {
    button.disabled=true;
    try {
      await rpc('sq_giveaway_enter',{p_giveaway_id:id});
      notify('You are entered. Good luck!','success');
      await feed();
    } catch(e) {notify(e.message,'error');button.disabled=false;}
  }
  async function adminList() {
    const root=$('#adminGiveawayList');if(!root)return;
    const seq=++adminRequest;root.innerHTML='<div class="admin-empty">Loading giveaways…</div>';
    try {
      const rows=await rpc('sq_admin_giveaways');
      if(seq!==adminRequest)return;
      root.innerHTML=rows.length?rows.map(g=>`<article class="admin-card sq-giveaway-admin-card">
        <div class="sq-giveaway-admin-heading"><div><span class="admin-eyebrow">${g.state==='open'&&new Date(g.ends_at)<=new Date()?'Ended · ready for draw':safe(g.state)}</span><h2>${safe(g.reward_name)}</h2><p>Created ${safe(date(g.created_at))} · Ends ${safe(date(g.ends_at))}</p></div><strong>${Number(g.entry_count).toLocaleString()} entered</strong></div>
        <p>${Number(g.valid_entries).toLocaleString()} currently valid entr${Number(g.valid_entries)===1?'y':'ies'} after provider reversals.</p>
        ${g.state==='drawn'? `<div class="sq-giveaway-winner"><strong>Winner: ${safe(g.winner_name||g.winner_user_id||'Account unavailable')}</strong><span>${safe(g.winner_email||'No verified contact email saved')} · ${safe(g.winner_user_id||'')}</span><small>Customer trade URL: ${safe(g.winner_trade_url||'No trade URL saved')}</small><small>Contact and deliver manually; the giveaway does not create a coin order.</small></div>
        ${g.delivered_at?`<p class="sq-giveaway-confirmed">Delivery recorded ${safe(date(g.delivered_at))}</p>`:
          `<form class="sq-giveaway-deliver" data-giveaway-deliver="${safe(g.id)}"><label>Steam trade message<textarea readonly rows="2">${safe(`SkinQuest giveaway ${g.id.slice(0,8)} - ${g.reward_name}`.slice(0,125))}</textarea></label><button class="admin-secondary-button" type="button" data-giveaway-copy-note>Copy message</button><label>Sent offer URL (optional)<input name="offer" maxlength="500" placeholder="https://steamcommunity.com/tradeoffer/123456789/" /></label><button class="admin-primary-button" type="submit" ${g.winner_trade_url?'':'disabled'}>Mark prize delivered</button><small>${g.winner_trade_url?'Use only after the winner has accepted the Steam offer.':'Ask the winner to save a valid Steam trade link, then refresh this page.'}</small></form>`}` : ''}
        ${g.state==='open'? `<div class="sq15-button-row">${new Date(g.ends_at)<=new Date()?
          `<button class="admin-primary-button" type="button" data-giveaway-draw="${safe(g.id)}">Draw winner</button>`:
          `<button class="admin-secondary-button" type="button" data-giveaway-cancel="${safe(g.id)}">Cancel giveaway</button>`}
          </div>`:''}
        ${g.state==='closed'?'<small>No valid entries when the draw closed.</small>':''}
      </article>`).join(''):'<div class="admin-empty"><strong>No giveaways yet</strong>Search for a reward above and create the first giveaway.</div>';
    } catch(e) {if(seq===adminRequest)root.innerHTML=`<div class="admin-empty"><strong>Could not load giveaways</strong>${safe(e.message)}</div>`;}
  }
  async function rewardSearch(query) {
    const root=$('#giveawayRewardResults');if(!root)return;
    const seq=++searchRequest;
    if(query.length<2){root.innerHTML='<p>Type at least two letters to find a catalog reward.</p>';return;}
    root.innerHTML='<p>Searching catalog…</p>';
    try {
      const data=await rpc('sq_admin_search_reward_items',{p_query:query,p_filter:'all',p_limit:12,p_offset:0});
      if(seq!==searchRequest)return;
      root.innerHTML=(data.items||[]).filter(r=>r.active).map(r=>`<button type="button" data-giveaway-reward="${r.id}"><strong>${safe(r.name)}</strong><small>${safe(r.market_name||'Catalog reward')} · ${Number(r.points_coins||r.points_cost||0).toLocaleString()} coins in shop</small></button>`).join('')||'<p>No active rewards found. Try another search.</p>';
    } catch(e){if(seq===searchRequest)root.innerHTML=`<p>${safe(e.message)}</p>`;}
  }
  async function create(event) {
    event.preventDefault();
    if(!selected)return notify('Select a reward from the search results.','error');
    const form=event.currentTarget,button=$('[type=submit]',form),value=$('#giveawayEndAt').value;
    const end=new Date(value);
    if(!value||Number.isNaN(end.getTime())||end<=new Date())return notify('Choose a future end time.','error');
    if(!await showConfirm(`Create a giveaway for ${selected.name} ending ${date(end)}? A verified survey reward received after creation will unlock entry.`,{title:'Publish giveaway?',confirmText:'Create giveaway'}))return;
    button.disabled=true;
    try {
      await rpc('sq_admin_giveaway_create',{p_reward_id:selected.id,p_ends_at:end.toISOString()});
      selected=null;$('#giveawaySelected').textContent='No reward selected';
      $('#giveawayRewardSearch').value='';$('#giveawayRewardResults').innerHTML='';
      $('#giveawayEndAt').value=local(Date.now()+8*86400000);
      notify('Giveaway created. Customers can now qualify and enter.','success');
      await adminList();
    }catch(e){notify(e.message,'error');}finally{button.disabled=false;}
  }
  async function draw(id,button) {
    if(!await showConfirm('Draw once from entries with a verified survey reward that has not been reversed? The winner is final and delivery is handled manually.',{title:'Draw giveaway winner?',confirmText:'Draw winner'}))return;
    button.disabled=true;
    try {const data=await rpc('sq_admin_giveaway_draw',{p_giveaway_id:id});notify(data.winner_user_id?'Winner drawn and recorded.':'No valid entries; giveaway closed.','success');await adminList();}
    catch(e){notify(e.message,'error');button.disabled=false;}
  }
  async function cancel(id,button) {
    if(!await showConfirm('Cancel this open giveaway? Existing entries remain recorded for audit, and the giveaway disappears from the customer page.',{title:'Cancel giveaway?',confirmText:'Cancel giveaway'}))return;
    button.disabled=true;
    try {await rpc('sq_admin_giveaway_cancel',{p_giveaway_id:id});notify('Giveaway cancelled.','success');await adminList();}
    catch(e){notify(e.message,'error');button.disabled=false;}
  }
  async function delivered(form) {
    const button=$('[type=submit]',form),offer=$('[name=offer]',form).value.trim();
    if(!await showConfirm('Confirm the winner accepted this Steam offer and received the stated prize? This records the delivery in the audit log.',{title:'Complete giveaway delivery?',confirmText:'Mark delivered'}))return;
    button.disabled=true;
    try {await rpc('sq_admin_giveaway_delivered',{p_giveaway_id:form.dataset.giveawayDeliver,p_trade_offer_url:offer||null});notify('Prize delivery recorded.','success');await adminList();}
    catch(e){notify(e.message,'error');button.disabled=false;}
  }
  function init() {
    if(!$('#giveawaysGrid')&&!$('#adminGiveawayList'))return;
    if(!eventsBound) {
      eventsBound=true;
      document.addEventListener('click',e=>{
        const button=e.target.closest('button');if(!button)return;
        if(button.dataset.giveawayEnter)enter(button.dataset.giveawayEnter,button);
        if(button.hasAttribute('data-giveaway-login'))openAuthModal('login');
        if(button.hasAttribute('data-giveaway-refresh'))feed();
        if(button.dataset.giveawayReward) {
          const root=$('#giveawayRewardResults');
          selected={id:Number(button.dataset.giveawayReward),name:$('strong',button).textContent};
          $('#giveawaySelected').textContent=selected.name;
          root.innerHTML='';$('#giveawayRewardSearch').value=selected.name;
        }
        if(button.dataset.giveawayDraw)draw(button.dataset.giveawayDraw,button);
        if(button.dataset.giveawayCancel)cancel(button.dataset.giveawayCancel,button);
        if(button.hasAttribute('data-giveaways-refresh'))adminList();
        if(button.hasAttribute('data-giveaway-copy-note')) {
          const field=$('textarea',button.closest('form'));
          if(!navigator.clipboard?.writeText){field.select();notify('Select and copy the highlighted message.','info');}
          else navigator.clipboard.writeText(field.value).then(()=>notify('Steam message copied.','success')).catch(()=>{field.select();notify('Select and copy the highlighted message.','info');});
        }
      });
      $('#giveawayCreateForm')?.addEventListener('submit',create);
      document.addEventListener('submit',event=>{if(event.target.matches('[data-giveaway-deliver]')){event.preventDefault();delivered(event.target);}});
      let timer;
      $('#giveawayRewardSearch')?.addEventListener('input',e=>{
        selected=null;$('#giveawaySelected').textContent='No reward selected';
        clearTimeout(timer);const query=e.target.value.trim();timer=setTimeout(()=>rewardSearch(query),220);
      });
      sb.auth.onAuthStateChange(()=>{if($('#giveawaysGrid'))setTimeout(feed,0);});
    }
    if($('#giveawaysGrid'))feed();
    if($('#giveawayEndAt'))$('#giveawayEndAt').value=local(Date.now()+8*86400000);
  }
  window.SQGiveaways={init,adminView:view=>{if(view==='giveaways')adminList();}};
})();
