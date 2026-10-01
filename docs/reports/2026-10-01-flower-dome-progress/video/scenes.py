import subprocess
CSS='''*{box-sizing:border-box;margin:0}body{width:1920px;height:1080px;overflow:hidden;font-family:-apple-system,"Helvetica Neue",Arial,sans-serif;color:#fff;
background:radial-gradient(1200px 700px at 80% 0%,#2a1f6e 0%,transparent 60%),radial-gradient(900px 600px at 0% 100%,#1b2a5e 0%,transparent 60%),#0f0f24;position:relative}
.logos{position:absolute;top:44px;right:60px;display:flex;align-items:center;gap:22px}.logos img.a{height:44px}.logos img.f{height:36px}.logos i{width:2px;height:40px;background:#4a4d70}
.kick{font-size:26px;letter-spacing:3px;text-transform:uppercase;color:#a99bff;font-weight:600}
h1{font-size:84px;font-weight:800;letter-spacing:-1px}h2{font-size:60px;font-weight:750;letter-spacing:-.5px;line-height:1.1}
.card{background:rgba(255,255,255,.06);border:1.5px solid rgba(169,155,255,.35);border-radius:22px;padding:34px 38px}
.num{display:inline-flex;width:58px;height:58px;border-radius:50%;background:#6c4cf5;align-items:center;justify-content:center;font-size:30px;font-weight:700;margin-bottom:18px}
.t{font-size:36px;font-weight:700;margin-bottom:10px}.d{font-size:27px;color:#c9cbe0;line-height:1.35}
.pill{display:inline-block;padding:8px 18px;border-radius:30px;font-size:24px;font-weight:600;margin:6px 8px 0 0}
.g{background:rgba(39,174,96,.2);color:#6fe3a0}.r{background:rgba(229,72,77,.2);color:#ff9a9d}.p{background:rgba(108,76,245,.3);color:#d6ccff}
.slot{position:absolute;border-radius:28px;background:#000;box-shadow:0 30px 80px rgba(0,0,0,.6)}
.shot{border-radius:16px;box-shadow:0 30px 80px rgba(0,0,0,.6);border:1.5px solid rgba(255,255,255,.15)}
'''
LOGOS='<div class="logos"><img class="a" src="aisee-logo.png"><i></i><img class="f" src="flowsxr-logo-light.svg"></div>'
S={}
S['title']=f'''<img src="e20.png" style="position:absolute;right:120px;top:150px;height:760px;opacity:.55;border-radius:20px">
<div style="position:absolute;left:130px;top:330px;width:1000px"><div class="kick">Gardens by the Bay · Flower Dome</div>
<h1 style="margin:22px 0 26px">AISEE-BIN</h1><div style="font-size:44px;color:#d6d8ee;line-height:1.3">Spoken navigation for blind and<br>low-vision visitors</div>
<div style="margin-top:40px"><span class="pill p">Progress · 1 Oct 2026</span><span class="pill p">Phone + AiSee glasses</span></div></div>
<div class="logos" style="top:200px;left:130px;right:auto"><img class="a" src="aisee-logo.png" style="height:56px"><i></i><img class="f" src="flowsxr-logo-light.svg" style="height:46px"></div>'''
steps=[("Scan the place","Walk the route once with a phone so it learns what the place looks like."),("Add the route","Draw walkways and add stops, hazards and what to say in our web editor."),("Guide the visitor","Phone or glasses recognise where they are and give spoken directions.")]
S['how']=LOGOS+'<div style="position:absolute;left:130px;top:150px"><div class="kick">How it works</div><h2 style="margin-top:14px">Three steps</h2></div><div style="position:absolute;left:130px;right:130px;top:380px;display:flex;gap:40px">'+''.join(f'<div class="card" style="flex:1;height:400px"><div class="num">{i+1}</div><div class="t">{a}</div><div class="d">{b}</div></div>' for i,(a,b) in enumerate(steps))+'</div>'
S['ways']=LOGOS+'''<div style="position:absolute;left:130px;top:150px"><div class="kick">Two ways to scan</div><h2 style="margin-top:14px">Testing both at the Flower Dome</h2></div>
<div style="position:absolute;left:130px;right:130px;top:380px;display:flex;gap:40px">
<div class="card" style="flex:1;height:420px"><div class="t" style="font-size:40px">A · Our app (ARKit)</div><div class="d">Scan and guide in one iPhone app. One walk gives map, route and stops.</div>
<div style="margin-top:26px"><span class="pill g">Smooth tracking</span><span class="pill g">Worked inside the dome</span><span class="pill r">iPhone only</span><span class="pill r">Weak at entrance</span></div></div>
<div class="card" style="flex:1;height:420px"><div class="t" style="font-size:40px">B · Immersal + our app</div><div class="d">Scan with Immersal Mapper, add the route in our editor, guide with our app.</div>
<div style="margin-top:26px"><span class="pill g">Phones and glasses</span><span class="pill g">Found the entrance fast</span><span class="pill r">~500 photos per map</span></div></div></div>'''
S['editor']=LOGOS+'<div style="position:absolute;left:130px;top:110px"><div class="kick">Web map editor · aiseebin.flowsxr.com</div></div><img class="shot" src="editor.png" style="position:absolute;left:210px;top:170px;width:1500px">'
S['site']=LOGOS+'''<div class="slot" style="left:150px;top:50px;width:370px;height:800px"></div><div class="slot" style="left:570px;top:50px;width:370px;height:800px"></div>
<div style="position:absolute;left:1080px;top:250px;width:720px"><div class="kick">On site · 1 October</div><h2 style="margin:16px 0 30px">Guided turn by turn to Points 1, 2 and 3</h2>
<div class="d" style="font-size:31px">Directions and a live map on the phone. Each stop is announced just before you reach it.</div>
<div style="margin-top:30px"><span class="pill g">Worked inside the dome</span></div></div>'''
S['entrance']=LOGOS+'''<div style="position:absolute;left:130px;top:150px"><div class="kick">The entrance</div><h2 style="margin-top:14px">Immersal recognised it instantly</h2></div>
<img class="shot" src="c45.png" style="position:absolute;left:130px;top:320px;width:960px">
<div class="slot" style="left:1330px;top:140px;width:420px;height:700px"></div>'''
S['next']=LOGOS+'''<div style="position:absolute;left:130px;top:150px"><div class="kick">Coming up</div><h2 style="margin-top:14px">What&#8217;s next</h2></div>
<div style="position:absolute;left:130px;right:130px;top:420px;display:flex;gap:30px">'''+''.join(f'<div class="card" style="flex:1;height:300px;{st}"><div class="kick" style="font-size:24px">{d}</div><div class="t" style="margin-top:16px">{a}</div><div class="d">{b}</div></div>' for d,a,b,st in [
("Scan","One Immersal map","Scan the whole route in daylight.",""),("Build","Immersal + ARKit","Combine them; extend existing maps.",""),("Test","Glasses on site","Full tour test at the Flower Dome.","border-color:#6fe3a0")])+'</div>'
for k,body in S.items():
    open(f'{k}.html','w').write(f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>{body}</body></html>')
    subprocess.run(['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--disable-gpu','--hide-scrollbars','--window-size=1920,1080',f'--screenshot=bg_{k}.png',f'file://{__import__("os").getcwd()}/{k}.html'],capture_output=True)
    print(k)
