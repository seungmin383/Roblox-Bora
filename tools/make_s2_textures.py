from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import math
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
fontpath=Path('C:/Windows/Fonts/segoeui.ttf')
def font(size):return ImageFont.truetype(str(fontpath),size) if fontpath.exists() else ImageFont.load_default(size=size)
im=Image.new('RGB',(1024,512),(8,15,22));d=ImageDraw.Draw(im)
for cx in [245,779]:
 d.arc((cx-174,82,cx+174,430),140,400,fill=(71,180,222),width=7)
 for k in range(21):
  a=math.radians(140+k*13);r=164;r2=146 if k%5==0 else 155
  d.line((cx+r*math.cos(a),256+r*math.sin(a),cx+r2*math.cos(a),256+r2*math.sin(a)),fill=(190,209,219),width=3)
d.text((245,205),'0',font=font(112),anchor='mm',fill=(230,240,245));d.text((245,302),'km/h',font=font(27),anchor='mm',fill=(154,174,188))
d.text((779,224),'P',font=font(92),anchor='mm',fill=(230,240,245));d.text((779,304),'READY',font=font(28),anchor='mm',fill=(98,203,175))
d.text((512,54),'BORA',font=font(27),anchor='mm',fill=(168,187,201));d.text((512,457),'000012 km',font=font(27),anchor='mm',fill=(168,187,201))
im.save(OUT/'BoraS2_Instruments.png')
im=Image.new('RGB',(1024,512),(18,29,38));d=ImageDraw.Draw(im)
for x in range(-300,1400,140):d.line((x,0,x+220,512),fill=(45,63,76),width=17)
for y in range(90,512,110):d.line((0,y,1024,y-100),fill=(45,63,76),width=17)
d.line((340,490,440,340,440,190,710,170),fill=(73,177,224),width=16);d.polygon([(440,286),(415,329),(465,329)],fill=(221,242,247))
d.rectangle((0,0,1024,66),fill=(8,16,24));d.text((35,30),'BORA  /  Navigation',font=font(28),anchor='lm',fill=(217,230,238));d.text((985,30),'12:00',font=font(28),anchor='rm',fill=(217,230,238))
d.rounded_rectangle((720,350,1000,488),radius=12,fill=(8,16,24));d.text((748,377),'Cabin',font=font(24),fill=(166,185,196));d.text((748,416),'22.0 C',font=font(38),fill=(226,237,242))
im.save(OUT/'BoraS2_Navigation.png')
print('Created flat cabin graphics without additional mesh detail.')
