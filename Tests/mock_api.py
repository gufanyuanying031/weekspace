import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.path == '/v1/chat/completions'
        assert 'Authorization' not in self.headers
        assert request['messages'][-1]['role'] == 'user'
        model = request['model']
        status = 401 if model == 'test-error' else 200
        body = {'error': {'message':'mock key rejected'}} if status == 401 else ({'choices':[{'message':{'content':'本地模拟复盘：测试通过。'}}]} if model == 'test-success' else {})
        if model == 'test-meeting':
            prompt = request['messages'][-1]['content']
            assert '虚构会议' in prompt and '持久化测试' not in prompt
            tasks = [
                {'title':'提交原型','assignee':'小林','deadline':'下周五','note':'附交互说明','evidence':'小林下周五提交原型，附交互说明。'},
                {'title':'整理测试数据','assignee':'小周','deadline':'','note':'','evidence':'小周整理测试数据。'},
                {'title':'确认部署环境','assignee':'','deadline':'','note':'负责人待确认','evidence':'还需要确认部署环境，负责人未定。'},
            ]
            body = {'choices':[{'message':{'content':json.dumps(tasks,ensure_ascii=False)}}]}
        data = json.dumps(body).encode()
        self.send_response(status); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self,*args): pass
server = HTTPServer(('127.0.0.1',0),Handler)
Path(__file__).resolve().parents[1].joinpath('build/verification/mock-port.txt').write_text(str(server.server_port))
print('Mock server ready on localhost',flush=True)
server.serve_forever()
