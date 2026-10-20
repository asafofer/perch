#!/usr/bin/env python3
# Writes a small synthetic Claude Code (terminal) transcript so Perch has a session to show. Usage: fake-session.py <cwd> <session-id>
import json, os, sys, datetime, uuid
cwd, sid = sys.argv[1], sys.argv[2]
os.makedirs(cwd, exist_ok=True)
d = os.path.expanduser('~/.claude/projects/' + cwd.replace('/', '-'))
os.makedirs(d, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc)
def ts(m): return (now - datetime.timedelta(minutes=m)).strftime('%Y-%m-%dT%H:%M:%S.000Z')
base = dict(isSidechain=False, userType='external', entrypoint='cli', cwd=cwd, sessionId=sid, version='2.1.0', gitBranch='main')
u1, a1, u2, a2 = (str(uuid.uuid4()) for _ in range(4))
lines = [
  dict(base, parentUuid=None, type='user', uuid=u1, timestamp=ts(30), message=dict(role='user', content='Make the settings page load faster')),
  dict(base, parentUuid=u1, type='assistant', uuid=a1, timestamp=ts(29), message=dict(id='msg_1', type='message', role='assistant', model='claude-sonnet-5-5',
       content=[dict(type='text', text='I will profile the settings page first.')], stop_reason='end_turn')),
  dict(base, parentUuid=a1, type='user', uuid=u2, timestamp=ts(12), message=dict(role='user', content='Go ahead and cache the font list')),
  dict(base, parentUuid=u2, type='assistant', uuid=a2, timestamp=ts(11), message=dict(id='msg_2', type='message', role='assistant', model='claude-sonnet-5-5',
       content=[dict(type='text', text='Cached the font list. The settings page now opens in 80 ms instead of 600 ms. Next: drop the unused theme loader.')], stop_reason='end_turn')),
  dict(type='ai-title', aiTitle='Faster settings page', sessionId=sid),
]
with open(f'{d}/{sid}.jsonl', 'w') as f:
    for l in lines: f.write(json.dumps(l) + '\n')
print(f'{d}/{sid}.jsonl')
