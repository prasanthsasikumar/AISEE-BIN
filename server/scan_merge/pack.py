import sys, json, base64, numpy as np
sys.argv=[sys.argv[0],"nus"]; sys.path.insert(0,"nustools")
from align import load, apply
pose={k:np.array(v) for k,v in json.load(open("nus/poses.json")).items()}
g=json.load(open("nus/merged.json"))
scans=[s for s in pose if s!="nus-computing"]
rng=np.random.default_rng(1)
P=[];S=[]
for i,s in enumerate(scans):
    p=apply(pose[s],load(s))
    p=p[rng.choice(len(p),min(len(p),7000),replace=False)]
    P.append(p);S.append(np.full(len(p),i,np.uint8))
P=np.vstack(P);S=np.concatenate(S)
c=np.median(P,0); P=P-c
q=np.round(P*100).astype("<i2")
data={"scans":scans,"center":c.tolist(),
 "pts":base64.b64encode(q.tobytes()).decode(),"scan":base64.b64encode(S.tobytes()).decode(),
 "nodes":[{"id":n["id"],"name":n["name"],"cat":n["category"],"x":round(n["x"]-c[0],2),"z":round(n["z"]-c[2],2),"y":(round(n["y"]-c[1],2) if "y" in n else None)} for n in g["pois"]],
 "edges":[[e["from"],e["to"]] for e in g["edges"]]}
json.dump(data,open("nus/viewdata.json","w"))
print(len(q), len(json.dumps(data))//1024,"KB", c)
