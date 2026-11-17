"""Record provenance and assemble a review sheet from the actual saved renders."""
from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont,ImageOps
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
audit=json.loads((OUT/'BoraS2_Audit.json').read_text());export=json.loads((OUT/'BoraS2_ExportValidation.json').read_text());assert audit['status']==export['status']=='pass'
prompt=('A complete unbranded modern Korean compact four-door sedan, production road car, semi-realistic game asset. Stock factory appearance, elegant silver paint, normal ride height, no spoiler, no body kit. Correct sedan proportions: long wheelbase, four identical circular wheels aligned under the fenders, gently arched roof, sloped windshield, distinct short trunk. Prioritize clean continuous large body surfaces: smooth hood, rounded fenders, crisp restrained shoulder crease, straight sill, symmetric left and right. All four doors CLOSED, perfectly flush with the body, narrow consistent panel gaps. Realistic thin window pillars and continuous smooth window shapes. Simple restrained bumper and headlamp shapes; grille is a shallow dark panel with a flat texture pattern, NOT individual bars or mesh lattice. No badges, logos, text, license plate lettering, tiny screws or ornament. Clean manufactured surfaces, no dents, melted edges or warped panels. Whole car only, no scene, no base.')
sources=ROOT/'assets/vehicles/source'
record={'date':'2026-10-18','virtualBrand':'BORA','model':'S2','prompt':prompt,'selectedTask':'b1e76032-3d84-48ca-98b7-dbf272ea6cab','candidates':[{'task':'0e991fa2-635f-4565-be8f-8e54275ea804','mode':'HD H3.1','trianglesShown':1897188,'verticesShown':989884,'credits':55,'review':'Reviewed on Tripo; not downloaded. Dense, production-like exterior with noisier surfaces.'},{'task':'b1e76032-3d84-48ca-98b7-dbf272ea6cab','mode':'Smart Mesh P2.0','requestedBudget':8000,'editableFacesShown':9343,'verticesShown':8466,'credits':100,'textureCredits':20,'review':'Selected for consistent body proportions and editable broad panel topology.'}],'credits':{'before':2385,'after':2210,'used':175},'sourceFiles':{},'cleanTriangles':audit['totalTriangles'],'dimensionsMetersIncludingMirrors':audit['dimensionsMeters'],'installedInPlace':False}
for name in ['BoraS2_Tripo_Quad_Source.glb','BoraS2_Tripo_Textured_Source.glb','BoraS2_Tripo_Quad_OBJ.zip']:
 p=sources/name;record['sourceFiles'][name]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(OUT/'BoraS2_Provenance.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
fontpath=Path('C:/Windows/Fonts/malgun.ttf');korean=fontpath.exists()
if not korean:fontpath=Path('C:/Windows/Fonts/segoeui.ttf')
font=ImageFont.truetype(str(fontpath),25) if fontpath.exists() else ImageFont.load_default(size=25)
labels=['차체 / 전면','후면','운전석 문 열림','운전석 1인칭'] if korean else ['Exterior','Rear','Door open','Driver view']
sheet=Image.new('RGB',(1440,1010),(19,25,32));draw=ImageDraw.Draw(sheet)
for i,(name,label) in enumerate(zip(['s2-clean-front.png','s2-clean-rear.png','s2-door-open.png','s2-cockpit.png'],labels)):
 x=(i%2)*720;y=(i//2)*505;im=Image.open(OUT/name).convert('RGB');im=ImageOps.contain(im,(720,465),Image.Resampling.LANCZOS)
 sheet.paste(im,(x+(720-im.width)//2,y+40+(465-im.height)//2));draw.text((x+20,y+6),label,font=font,fill=(220,231,240))
sheet.save(OUT/'BoraS2_Overview.jpg',quality=94)
n=audit['totalTriangles'];partcount=export['nativePartCount']
readme=f'''# BORA S2 차량 정리본

이 폴더의 `BoraS2_Clean.blend`가 최종 편집 파일입니다. `BoraS2_Clean.glb`에는 차량과 재질만 들어 있으며, 사진용 바닥·조명·카메라는 내보내지 않았습니다. 현재 `Ro.rbxlx`의 차량은 교체하지 않았습니다.

## 확인할 파일

- `BoraS2_Overview.jpg`: 전면·후면·문 열림·1인칭 확인용 이미지
- `BoraS2_Clean.blend`: 텍스처를 내장한 편집 파일. Body / DoorFL·FR·RL·RR / WheelFL·FR·RL·RR / Steering 컬렉션으로 구분했습니다.
- `BoraS2_Clean.glb`: 일반 가져오기용 자산
- `native/manifest.json` 및 `.mesh`: 기존 프로젝트 방식의 피벗 상대좌표 메시. {partcount}개 파트이며 개별 파트는 8,000삼각형 이하입니다.

## 정리한 부분

Tripo에서 차 전체를 두 후보로 생성하고 P2.0 후보를 선택했습니다. 이 후보의 차체 표면을 기준으로 문을 분리했습니다. 차체·후드·범퍼의 큰 곡면은 해당 원본의 표면 표본으로 맞추고, 유리·지붕·창 하단 연결·실내·바퀴·핸들은 이 차의 치수에 맞춰 정리했습니다. 그릴은 얕은 패널과 텍스처 무늬입니다. 계기판과 내비 화면도 텍스처이며, 실제 브랜드 엠블럼과 바퀴 로고는 제거했습니다.

실내는 1인칭 기본 시야용으로 단순화했습니다. 외장·문·유리의 같은 곡면을 기준으로 맞췄으며, 이전 S1의 문이나 지붕을 가져다 붙이지 않았습니다. 저장된 블렌드의 사진용 실내 보조 조명은 게임 자산에 포함하지 않습니다.

## 검사와 현재 범위

- 저장본 재로드 기준 차량 전체 **{n:,}삼각형**
- 모든 메시의 열린 경계·비다양체 모서리·퇴화 삼각형·잘못된 좌표/UV/노멀: 검사 통과
- 네 타이어의 외경 반지름 0.338m, 같은 원형 단면·정렬·공용 그룹 피벗 확인
- GLB와 native 파일의 인덱스·노멀·UV·삼각형 수·텍스처 경로 확인
- 보호한 기존 파일 변경 없음. Place는 최상위 `Ro.rbxlx` 하나입니다.

이는 모델 정리 및 파일 검사 결과입니다. Roblox Studio 실행, 기존 차량 교체, 주행·탑승·문 충돌 시험은 이번 작업에 포함하지 않았습니다. 새 외장으로 교체할 때 기존 섀시와 조작 스크립트에 그룹·치수를 맞춰야 합니다.

## 원본 기록

선정 작업: https://studio.tripo3d.ai/ko/workspace/generate/b1e76032-3d84-48ca-98b7-dbf272ea6cab

생성 두 번과 텍스처 한 번에 총 175크레딧을 사용했습니다. 원본은 `../source/BoraS2_*`에 유지합니다. 세부 이력은 `BoraS2_Provenance.json`, 검사 결과는 `BoraS2_Audit.json`, `BoraS2_SkinInspection.json`, `BoraS2_ExportValidation.json`입니다.

## 다시 생성하는 순서

`make_s2_textures.py` → `prepare_s2_scene.py` → `clean_s2_sedan.py` → `finalize_s2_sedan.py` → `qa_s2_sedan.py` → `validate_s2_exports.py` → `package_s2_delivery.py`

모든 도구는 자산 폴더에서만 작업하며, Place를 만들거나 Studio를 실행하지 않습니다.
'''
(OUT/'README.md').write_text(readme,encoding='utf-8')
print(json.dumps({'overview':str(OUT/'BoraS2_Overview.jpg'),'triangles':n,'credits':175,'installedInPlace':False}))
