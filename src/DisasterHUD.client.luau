-- [BoraDisaster] Replicated round status and local countdown.
local Run=game:GetService('RunService')
local player=game:GetService('Players').LocalPlayer
local state=game:GetService('ReplicatedStorage'):WaitForChild('BoraDisasterState')

local gui=Instance.new('ScreenGui')
gui.Name='BoraDisasterHUD'
gui.ResetOnSpawn=false
gui.DisplayOrder=12
gui.Parent=player:WaitForChild('PlayerGui')

local panel=Instance.new('Frame')
panel.AnchorPoint=Vector2.new(.5,0)
panel.Position=UDim2.new(.5,0,0,12)
panel.Size=UDim2.new(.94,0,0,76)
panel.BackgroundColor3=Color3.fromRGB(22,26,34)
panel.BackgroundTransparency=.10
panel.BorderSizePixel=0
panel.Parent=gui
local size=Instance.new('UISizeConstraint')
size.MaxSize=Vector2.new(410,76)
size.Parent=panel
local corner=Instance.new('UICorner')
corner.CornerRadius=UDim.new(0,12)
corner.Parent=panel
local border=Instance.new('UIStroke')
border.Color,border.Transparency=Color3.fromRGB(220,227,237),.72
border.Parent=panel

local function line(position,size,font,textSize,alignment)
	local label=Instance.new('TextLabel')
	label.Position,label.Size=position,size
	label.Font,label.TextSize=font,textSize
	label.TextColor3,label.TextXAlignment=Color3.fromRGB(241,244,249),alignment
	label.BackgroundTransparency=1
	label.TextTruncate=Enum.TextTruncate.AtEnd
	label.Parent=panel
	return label
end

local title=line(UDim2.fromOffset(15,9),UDim2.new(1,-90,0,28),Enum.Font.GothamBold,20,Enum.TextXAlignment.Left)
local details=line(UDim2.fromOffset(15,41),UDim2.new(1,-24,0,23),Enum.Font.GothamMedium,14,Enum.TextXAlignment.Left)
details.TextColor3=Color3.fromRGB(207,217,234)
local countdown=line(UDim2.new(1,-75,0,8),UDim2.fromOffset(60,28),Enum.Font.GothamBold,20,Enum.TextXAlignment.Right)

local fallback={Waiting='플레이어 대기 중',Intermission='다음 라운드 준비',Warning='운석우 경보',Active='운석우',Results='라운드 종료'}
local function refresh()
	local phase=state:GetAttribute('Phase')
	local alive,total=state:GetAttribute('Alive') or 0,state:GetAttribute('Entrants') or 0
	local playing=player:GetAttribute('BoraInRound')==true
	title.Text=fallback[phase] or fallback.Waiting
	countdown.TextColor3=if phase=='Warning' or phase=='Active' then Color3.fromRGB(255,183,105) else Color3.fromRGB(241,244,249)
	if phase=='Warning' and playing then
		details.Text='노란 경계를 벗어나면 탈락합니다'
	elseif phase=='Warning' or phase=='Active' then
		details.Text=if playing then ('붉은 낙하지점 피하기   ·   생존 %d/%d'):format(alive,total) else '다음 라운드에서 참가할 수 있어요'
	elseif phase=='Results' then
		details.Text=('생존 %d/%d명   ·   내 생존 %d회'):format(alive,total,player:GetAttribute('BoraSurvivals') or 0)
	elseif phase=='Intermission' then
		details.Text='시작하면 보라동으로 이동합니다'
	else
		details.Text=''
	end
end
for _,key in {'Phase','Alive','Entrants'} do state:GetAttributeChangedSignal(key):Connect(refresh) end
for _,key in {'BoraInRound','BoraSurvivals'} do player:GetAttributeChangedSignal(key):Connect(refresh) end
refresh()

local last=nil
Run.Heartbeat:Connect(function()
	local deadline=state:GetAttribute('EndsAt') or 0
	local remaining=if deadline>0 then math.max(0,math.ceil(deadline-workspace:GetServerTimeNow())) else -1
	if remaining~=last then
		last=remaining
		countdown.Text=if remaining>=0 then ('0:%02d'):format(remaining) else ''
	end
end)
