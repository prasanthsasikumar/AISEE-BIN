import sys, json, base64, numpy as np
sys.argv=[sys.argv[0],"nus"]; sys.path.insert(0,"nustools")
from align import load, rows, anch, yaw_of
pose={k:np.array(v) for k,v in json.load(open("nus/poses.json")).items()}
rng=np.random.default_rng(2)
out=[]; x_off=None
placed=[s for s in rows if s in pose]
# where to park unplaced scans: right of everything placed
maxx=max(pose[s][0,3] for s in placed)+40
k=0
for s in rows:
    p=load(s); p=p[rng.choice(len(p),min(len(p),3500),replace=False)]
    q=np.round(p*100).astype("<i2")
    g=rows[s]["graph"]
    nodes=[]
    for n in g["pois"]:
        a=anch[s].get(n["id"])
        nodes.append({"id":n["id"],"name":n["name"],"cat":n["category"],"x":round(n["x"],2),"z":round(n["z"],2),"y":round(a[1],2) if a else None})
    if s in pose:
        m=pose[s]; pl={"yaw":round(float(-yaw_of(m)),5),"tx":round(float(m[0,3]),3),"ty":round(float(m[1,3]),3),"tz":round(float(m[2,3]),3)}
    else:
        c=np.median(p,0); pl={"yaw":0,"tx":round(float(maxx+k*45-c[0]),2),"ty":0,"tz":round(float(-c[2]),2)}; k+=1
    out.append({"scan":s,"placed":s in pose,"pts":base64.b64encode(q.tobytes()).decode(),"nodes":nodes,
                "edges":[[e["from"],e["to"]] for e in g["edges"]],"pl":pl})
json.dump(out,open("nus/aligndata.json","w"))
print(len(json.dumps(out))//1024,"KB")
