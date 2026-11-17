"""Package the verified local repair views without changing the 3D assets."""
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
audit=json.loads((OUT/'BoraS2_FitFix_Audit.json').read_text());clear=json.loads((OUT/'BoraS2_FitFix_Clearance.json').read_text());export=json.loads((OUT/'BoraS2_FitFix_ExportValidation.json').read_text())
assert audit['status']==clear['status']==export['status']=='pass'
assert audit['totalTriangles']==export['totalTriangles']
canvas=Image.new('RGB',(1600,652),(25,31,39));draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',23)
for x,label,name in [(0,'앞코 · 범퍼 접합 수정','s2-fit-nose.png'),(800,'앞유리 · 대시보드 간섭 수정','s2-fit-glass.png')]:
 im=Image.open(OUT/name).convert('RGB');im=im.resize((800,600),Image.Resampling.LANCZOS);canvas.paste(im,(x,45));draw.text((x+18,9),label,font=font,fill=(231,236,242))
canvas.save(OUT/'BoraS2_FitFix_Review.jpg',quality=93)
readme=OUT/'BoraS2_FitFix_README.md';s=readme.read_text(encoding='utf-8');s=s.replace('42,908삼각형',f"{audit['totalTriangles']:,}삼각형");readme.write_text(s,encoding='utf-8')
print(json.dumps({'status':'pass','triangles':audit['totalTriangles'],'objects':len(audit['objects']),'frontRayChecks':clear['noseCoverageRays'],'insertSamples':sum(r['surfaceSamples'] for r in clear['frontInsertChecks']),'installedInPlace':False}))
