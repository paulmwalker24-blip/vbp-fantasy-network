import fs from 'node:fs';

const base='https://api.sleeper.app/v1';
const currentId='1314734374628884480';
const get=async p=>{const r=await fetch(base+p); if(!r.ok) throw new Error(`${p}: ${r.status}`); return r.json();};
const isKeeper=p=>{const v=p?.is_keeper??p?.metadata?.is_keeper??p?.metadata?.keeper; return v===true||v===1||v==='1'||v==='true'||v==='yes';};

const current=await get(`/league/${currentId}`);
const seasons=[];
let lid=current.previous_league_id;
for(let i=0; lid && i<10; i++){
  const league=await get(`/league/${lid}`);
  const drafts=await get(`/league/${lid}/drafts`);
  const draft=drafts.find(d=>String(d.draft_id)===String(league.draft_id)) || [...drafts].sort((a,b)=>Number(b.created||0)-Number(a.created||0))[0] || null;
  const picks=draft?await get(`/draft/${draft.draft_id}/picks`):[];
  const users=await get(`/league/${lid}/users`);
  const rosters=await get(`/league/${lid}/rosters`);
  const userMap=Object.fromEntries(users.map(u=>[String(u.user_id),u]));
  const rosterOwner=Object.fromEntries(rosters.map(r=>[Number(r.roster_id), r.owner_id?String(r.owner_id):null]));
  const keepers=picks.filter(isKeeper).map(p=>{
    const rid=Number(p.roster_id);
    const ownerId=rosterOwner[rid]||null;
    const u=ownerId?userMap[ownerId]:null;
    const manager=u?.display_name || u?.username || ownerId || `Roster ${rid}`;
    const name=[p.metadata?.first_name,p.metadata?.last_name].filter(Boolean).join(' ') || String(p.player_id);
    return {season:String(league.season),player_id:String(p.player_id),player:name,position:p.metadata?.position||null,round:Number(p.round),pick_no:Number(p.pick_no),roster_id:rid,owner_id:ownerId,manager};
  });
  seasons.push({season:String(league.season),league_id:String(league.league_id),league_name:league.name,draft_id:draft?String(draft.draft_id):null,keepers});
  lid=league.previous_league_id;
}
seasons.sort((a,b)=>Number(a.season)-Number(b.season));
const totals=new Map();
for(const s of seasons){
  for(const k of s.keepers){
    const key=k.player_id;
    if(!totals.has(key)) totals.set(key,{player_id:key,player:k.player,position:k.position,total_keeper_uses:0,uses:[]});
    const t=totals.get(key); t.total_keeper_uses++; t.uses.push({season:k.season,manager:k.manager,roster_id:k.roster_id,round:k.round,pick_no:k.pick_no});
  }
}
const result={checked_at:new Date().toISOString(),current_league:{id:currentId,name:current.name,season:current.season},seasons,players:[...totals.values()].sort((a,b)=>a.player.localeCompare(b.player))};
fs.mkdirSync('dist',{recursive:true});
fs.writeFileSync('dist/keeper3-ledger.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
