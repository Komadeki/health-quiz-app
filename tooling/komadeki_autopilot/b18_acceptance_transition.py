#!/usr/bin/env python3
from __future__ import annotations
import csv, json, subprocess, sys
from pathlib import Path
REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'tooling'/'question_bank'))
from ai_governance import candidate_fingerprint,promote_ai_governed_candidates
from expansion import validate_expansion_batch
BANK=REPO/'question_banks'/'drone_second_class'; AUTHORING=BANK/'authoring'; BATCH=AUTHORING/'batches'/'batch_018'; STATE_PATH=REPO/'tooling'/'komadeki_autopilot'/'drone_state.json'
ALL=tuple(f'B18-RULE-C{i:03d}' for i in range(1,7)); AUTHOR_ID='chatgpt-b18-rules-author-r1'; REVIEWER_ID='autopilot-b18-residual-reviewer-r1'; DIRECTOR_ID='chatgpt-primary-director-b18-residual-r1'
state=json.loads(STATE_PATH.read_text(encoding='utf-8'))
if state.get('state_epoch')!=126 or state.get('next_atomic_objective')!='MATERIALIZE_B18_ACCEPTANCE_PACKETS_6': raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")
contract=json.loads((AUTHORING/'residual_proposition_completion_contract_2026-08-25.json').read_text(encoding='utf-8'))
if contract.get('completion_target',{}).get('fixed_question_count') is not None or contract.get('tier_policy',{}).get('future_authoring')!='TIER_A_NEW_PROPOSITION_ONLY': raise SystemExit('residual-only contract drift')
with (BATCH/'candidates.csv').open(encoding='utf-8',newline='') as h: rows={r['candidate_id']:r for r in csv.DictReader(h)}
if set(rows)!=set(ALL) or any(rows[c]['state']!='AI_PRE_ACCEPT' or rows[c]['permanent_question_id'].strip() for c in ALL): raise SystemExit('unexpected B18 candidate set/state')
review=json.loads((BATCH/'independent_review_r1.json').read_text(encoding='utf-8')); review_by={d['candidate_id']:d for d in review['decisions']}
if review.get('summary')!={'reviewed':6,'accept':6,'reject':0,'rework':0,'hold':0} or set(review_by)!=set(ALL) or any(review_by[c].get('decision')!='ACCEPT' for c in ALL): raise SystemExit('B18 review decision drift')
if review.get('identity_separation')!='PASS' or review.get('author_identity_checked')!=AUTHOR_ID or review.get('reviewer',{}).get('id')!=REVIEWER_ID: raise SystemExit('B18 review identity drift')
if review.get('residual_only_gate',{}).get('controlled_variant_allowance_used') is not False or review.get('residual_only_gate',{}).get('numeric_quota_used') is not False: raise SystemExit('B18 residual review gate drift')
director=json.loads((BATCH/'director_adjudication_r1.json').read_text(encoding='utf-8'))
if director.get('summary')!={'accept':6,'reject':0,'rework':0,'hold':0} or set(director.get('accepted_candidate_ids',[]))!=set(ALL) or director.get('rejected_candidate_ids',[]): raise SystemExit('B18 Director decision drift')
if director.get('identity_separation_checked') is not True or director.get('author_identity')!=AUTHOR_ID or director.get('reviewer_identity')!=REVIEWER_ID or director.get('director',{}).get('id')!=DIRECTOR_ID or len({AUTHOR_ID,REVIEWER_ID,DIRECTOR_ID})!=3: raise SystemExit('B18 Director identity drift')
director_rationale=' '.join(str(x).strip() for x in director.get('director_findings',[]) if str(x).strip())
if not director_rationale: raise SystemExit('B18 Director rationale missing')
packets=BATCH/'acceptance_packets'; packets.mkdir(exist_ok=True)
if list(packets.glob('*.json')): raise SystemExit('partial B18 packet state detected')
for cid in ALL:
 c=rows[cid]
 packet={'schema_version':'1.0','candidate_id':cid,'candidate_state':'AI_PRE_ACCEPT','candidate_fingerprint':candidate_fingerprint(c),'actors':{'author':{'id':AUTHOR_ID,'role':'AI_AUTHOR'},'reviewer':{'id':REVIEWER_ID,'role':'AI_REVIEWER'},'director':{'id':DIRECTOR_ID,'role':'AI_DIRECTOR'}},'evidence':{'source':{k:c[k] for k in ('source_id','source_version','source_locator')},'answer_defining_proposition':c['answer_defining_proposition'],'tested_misconception':c['tested_misconception'],'reasoning_path':c['reasoning_path'],'collision':{'released_bank_checked':True,'canonical_drafts_checked':True,'batch_checked':True,'note':c['collision_note']}},'independent_review':{'decision':'ACCEPT','rationale':review_by[cid]['rationale']},'director_adjudication':{'decision':'ACCEPT','rationale':director_rationale},'requested_state':'AI_GOVERNED_ACCEPT'}
 (packets/f'{cid}.json').write_text(json.dumps(packet,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
promote_ai_governed_candidates(BATCH,ALL)
with (BATCH/'candidates.csv').open(encoding='utf-8',newline='') as h: after={r['candidate_id']:r for r in csv.DictReader(h)}
if any(after[c]['state']!='READY_FOR_ID' or after[c]['permanent_question_id'] for c in ALL) or {p.stem for p in packets.glob('*.json')}!=set(ALL): raise SystemExit('B18 promotion/packet drift')
with (AUTHORING/'questions.csv').open(encoding='utf-8',newline='') as h:
 if sum(1 for _ in csv.DictReader(h))!=365: raise SystemExit('canonical baseline changed')
if len(json.loads((AUTHORING/'released_questions.json').read_text(encoding='utf-8'))['released_questions'])!=188: raise SystemExit('released baseline changed')
meta=json.loads((AUTHORING/'bank.json').read_text(encoding='utf-8')); runtime=json.loads((BANK/meta['runtime_output']).read_text(encoding='utf-8'))
if sum(len(u.get('cards',[])) for d in runtime.get('decks',[]) for u in d.get('units',[]))!=188: raise SystemExit('runtime baseline changed')
state['observed_main']=subprocess.check_output(['git','rev-parse','origin/main'],text=True).strip(); state['state_epoch']=127; state['next_atomic_objective']='ALLOCATE_AND_INTEGRATE_B18_ACCEPTED_6'; STATE_PATH.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
errors=validate_expansion_batch(BATCH)
if errors: raise SystemExit('B18 expansion validation failed: '+' | '.join(errors))
