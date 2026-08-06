import fs from 'node:fs';
const base='https://api.sleeper.app/v1';
const currentId='1314734374628884480';
const openIds=new Set([6,10,11]);
const get=async p=>{const r=await fetch(base+p);if(!r.ok)throw new Error(`${p}: ${r.status}`);return r.json()};
const isKeeper=p=>{const v=p?.is_keeper??p?.metadata?.is_keeper??p?.metadata?.keeper;return v===true||v===1||v==='1'||v==='true'||v==='yes'};
const current=await get(`/league/${currentId}`);
const rosters=await get(`/league/${currentId}/rosters`);
const players=await get('/players/nfl');
const targets=rosters.filter(r=>openIds.has(Number(r.roster_id)));
const ids=new Set(targets.flatMap(r=>(r.players||[]).map(String)));
const seasons=[];
let lid=current.previous_league_id;
for(let i=0;lid&&i<10;i++){
  const l=await get(`/league/${lid}`);
  const drafts=await get(`/league/${lid}/drafts`);
  const d=drafts.find(x=>String(x.draft_id)===String(l.draft_id))||[...drafts].sort((a,b)=>Number(b.created||0)-Number(a.created||0))[0]||null;
  const picks=d?await get(`/draft/${d.draft_id}/picks`):[];
  seasons.push({season:String(l.season),league_id:String(l.league_id),draft_id:d?String(d.draft_id):null,picks:picks.filter(p=>ids.has(String(p.player_id))).map(p=>({player_id:String(p.player_id),round:Number(p.round),pick_no:Number(p.pick_no),roster_id:p.roster_id==null?null:Number(p.roster_id),is_keeper:isKeeper(p),raw_is_keeper:p.is_keeper??null,metadata:p.metadata??null}))});
  lid=l.previous_league_id;
}
seasons.sort((a,b)=>Number(b.season)-Number(a.season));
const latest=seasons[0]?.season||null;
const name=id=>String(id).length<=3?String(id):(players[String(id)]?.full_name||`${players[String(id)]?.first_name||''} ${players[String(id)]?.last_name||''}`.trim()||String(id));
const openings=targets.map(r=>({roster_id:Number(r.roster_id),players:(r.players||[]).map(id=>{
  const history=seasons.map(s=>{const p=s.picks.find(x=>x.player_id===String(id));return p?{season:s.season,...p}:null}).filter(Boolean);
  const last=history.find(x=>x.season===latest)||null;
  let uses=0;
  if(last){for(const s of seasons){const e=history.find(x=>x.season===s.season);if(!e||!e.is_keeper)break;uses++}}
  let status='ELIGIBLE',cost=last?last.round-2:null;
  if(!last){status='NO_VERIFIED_2025_DRAFT_COST';cost=null}else if(last.round<3){status='INELIGIBLE_ROUND';cost=null}else if(uses>=2){status='INELIGIBLE_MAX_TENURE';cost=null}
  return {player_id:String(id),name:name(id),position:String(id).length<=3?'DEF':players[String(id)]?.position||null,status,keeper_cost_2026_round:cost,latest_round:last?.round??null,latest_was_keeper:last?.is_keeper??null,consecutive_keeper_uses:uses,sleeper_note:r.metadata?.[`p_nick_${id}`]||null,history};
})}));
const result={checked_at:new Date().toISOString(),league:{id:currentId,name:current.name,season:current.season},rule:{minimum_round:3,penalty_rounds:2,max_keeper_uses:2},season_chain:seasons.map(s=>({season:s.season,league_id:s.league_id,draft_id:s.draft_id})),openings};
const body=JSON.stringify(result);
await fetch('https://vbpkeeper20260806.requestcatcher.com/audit',{method:'POST',headers:{'content-type':'application/json'},body});
fs.mkdirSync('dist',{recursive:true});
fs.writeFileSync('dist/index.html','<!doctype html><title>Keeper audit complete</title><p>Complete</p>');
fs.writeFileSync('dist/keeper-audit.json',JSON.stringify(result,null,2));
