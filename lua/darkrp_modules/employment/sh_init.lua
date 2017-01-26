local EmployableTeams = {"TEAM_SECURITYGUARD"}

local PlayerMeta = FindMetaTable("Player")
local MinOfferDistanceSqr = GM.Config.minHitDistance * GM.Config.minHitDistance

function PlayerMeta:IsEmployable()
	for _, v in pairs(EmployableTeams) do
		if self:Team() == _G[v] then
			return true
		end
	end
	return false
end

DarkRP.registerDarkRPVar("Employer", net.WriteEntity, net.ReadEntity)
DarkRP.registerDarkRPVar("EmploymentWage", fn.Curry(fn.Flip(net.WriteInt), 2)(32), fn.Partial(net.ReadInt, 32))

function PlayerMeta:IsEmployed()
    return self:getDarkRPVar("Employer") ~= nil
end

function PlayerMeta:GetEmployer()
    return self:getDarkRPVar("Employer")
end

function PlayerMeta:GetEmploymentWage()
    return self:getDarkRPVar("EmploymentWage") or 0
end

DarkRP.declareChatCommand{
    command = "offeremployment",
    description = "Offer employment to the player you're looking at",
    delay = 5,
    condition = fn.Compose{fn.Not, fn.Null, fn.Curry(fn.Filter, 2)(PlayerMeta.IsEmployable), player.GetAll}
}

DarkRP.declareChatCommand{
    command = "quitemployment",
    description = "End your current employment",
    delay = 5,
    condition = fn.Compose{fn.Not, fn.Null, fn.Curry(fn.Filter, 2)(PlayerMeta.IsEmployed), player.GetAll}
}

DarkRP.declareChatCommand{
    command = "employment",
    description = "Open employee view menu",
    delay = 1
}

DarkRP.declareChatCommand{
    command = "fireemployee",
    description = "Fire an employee",
    delay = 2
}

DarkRP.declareChatCommand{
    command = "employeeraise",
    description = "Give an employee a raise",
    delay = 1
}

function DarkRP.hooks:CanOfferEmployment(Employee, Employer)
	if not Employee:IsEmployable() then return false, "Player is not employable" end
	if Employee:GetPos():DistToSqr(Employer:GetPos()) > MinOfferDistanceSqr then return false, "Player too far away" end
	if Employee == Employer then return false, "Cannot hire yourself" end
	if Employee:IsEmployed() then return false, "Employee already employed" end
	if Employer:GetEmployer() == Employee then return false, "You cannot employ your employer" end
	return true
end

if SERVER then
	local function GiveEmployment(Employee, Employer, Wage)
		DarkRP.notify(Employee, 0, 8, "Welcome to your new job working for "..Employer:Nick())
		
		Employee:setDarkRPVar("Employer", Employer)
		Employee:setDarkRPVar("EmploymentWage", Wage)
		
		DarkRP.payPlayer(Employer, Employee, Wage)
		DarkRP.notify(Employee, 0, 6, Employer:Nick().." has paid you $"..Wage.." for your employment")
		DarkRP.notify(Employer, 0, 6, "You have paid "..Employee:Nick().." $"..Wage.." wage")
	end

	local function EndEmployment(Employee, Reason)
		local Employer = Employee:GetEmployer()
		if IsValid(Employer) then
			DarkRP.notify(Employer, 1, 8, "Your employment of "..Employee:Nick().." has ended for reason: "..Reason)
		end
		DarkRP.notify(Employee, 1, 8, "Your employment by "..Employer:Nick().." has ended for reason: "..Reason)
		Employee:setDarkRPVar("Employer", nil)
		Employee:setDarkRPVar("EmploymentWage", nil)
	end
	
	function PlayerMeta:payDay()
		if not IsValid(self) then return end
		if not self:isArrested() then
			local amount = math.floor(DarkRP.retrieveSalary(self) or GAMEMODE.Config.normalsalary)
			local suppress, message, hookAmount = hook.Call("playerGetSalary", GAMEMODE, self, amount)
			amount = hookAmount or amount

			if amount == 0 or not amount then
				if not suppress then DarkRP.notify(self, 4, 4, message or DarkRP.getPhrase("payday_unemployed")) end
			else
				self:addMoney(amount)
				if not suppress then DarkRP.notify(self, 4, 4, message or DarkRP.getPhrase("payday_message", DarkRP.formatMoney(amount))) end
			end
			if self:IsEmployed() then
				local Employer = self:GetEmployer()
				local Wage = self:GetEmploymentWage()
				if Employer:canAfford(Wage) then
					DarkRP.payPlayer(Employer, self, Wage)
					DarkRP.notify(self, 0, 6, Employer:Nick().." has paid you $"..Wage.." for your employment")
					DarkRP.notify(Employer, 0, 6, "You have paid "..self:Nick().." $"..Wage.." wage")
				else
					EndEmployment(self, "Employer cannot afford wage")
				end
			end
		else
			DarkRP.notify(self, 4, 4, DarkRP.getPhrase("payday_missed"))
		end
	end
	
	local QuestionCallback
	local function OfferEmployment(Employee, Employer, Wage)
		local CanRequest, Message = hook.Call("CanOfferEmployment", DarkRP.hooks, Employee, Employer)
		
		if not CanRequest then
			DarkRP.notify(Employer, 1, 4, Message)
			return
		end
		
		DarkRP.createQuestion("Accept employment offer from "..Employer:Nick().." for "..DarkRP.formatMoney(Wage),
			"employmentoffer" .. Employee:UserID() .. "|" .. Employer:UserID(),
			Employee,
			20,
			QuestionCallback,
			Employer,
			Wage
		)
		
		DarkRP.notify(Employer, 0, 4, "Employment offered!")
	end
	
	function QuestionCallback(Answer, Employee, Employer, Wage)
		if not IsValid(Employee) or not Employee:IsEmployable() then return end
		if not IsValid(Employer) then return end
		
		if not IsValid(Employee) then
			DarkRP.notify(Employer, 1, 4, "The target has left the server!")
			return
		end
		
		if not tobool(Answer) then
			DarkRP.notify(Employer, 1, 4, "The target has declined your offer!")
			return
		end
		
		if not Employer:canAfford(Wage) then
			DarkRP.notify(Employer, 1, 4, DarkRP.getPhrase("cant_afford", "employee"))
			return
		end
		
		if Employee:IsEmployed() then
			DarkRP.notify(Employer, 1, 4, "The target is already employed!")
			return
		end
		
		GiveEmployment(Employee, Employer, Wage)
		
		DarkRP.notify(Employer, 0, 6, "The target has accepted your employment offer!")
	end
	
	DarkRP.defineChatCommand("offeremployment", function(Plr, Args)
		Args = string.Explode(" ", Args)
		if #Args ~= 2 then
			DarkRP.notify(ply, 1, 4, DarkRP.getPhrase("invalid_x", DarkRP.getPhrase("arguments"), ""))
			return ""
		end
		local Employee = Player(tonumber(Args[1] or -1) or -1)
		local Wage = tonumber(Args[2])
		if not IsValid(Employee) or not Employee:IsPlayer() or not Wage then
			DarkRP.notify(ply, 1, 4, DarkRP.getPhrase("invalid_x", DarkRP.getPhrase("arguments"), ""))
			return ""
		end
		
		OfferEmployment(Employee, Plr, Wage)
		return ""
	end)
	
	DarkRP.defineChatCommand("quitemployment", function(Plr, Args)
		EndEmployment(Plr, "Employee has quit")
		return ""
	end)
	
	DarkRP.defineChatCommand("employment", function(Plr, Args)
		Plr:ConCommand("employment")
		return ""
	end)
	
	DarkRP.defineChatCommand("fireemployee", function(Plr, Args)
		Args = string.Explode(" ", Args)
		if #Args ~= 1 then
			DarkRP.notify(ply, 1, 4, DarkRP.getPhrase("invalid_x", DarkRP.getPhrase("arguments"), ""))
			return ""
		end
		local Employee = Player(tonumber(Args[1] or -1) or -1)
		if not IsValid(Employee) or not Employee:IsPlayer() then
			DarkRP.notify(ply, 1, 4, DarkRP.getPhrase("invalid_x", DarkRP.getPhrase("arguments"), ""))
			return ""
		end
		
		EndEmployment(Employee, "Employee has been fired")
		return ""
	end)
	
	DarkRP.defineChatCommand("employeeraise", function(Plr, Args)
		Args = string.Explode(" ", Args)
		if #Args ~= 2 then
			DarkRP.notify(ply, 1, 4, DarkRP.getPhrase("invalid_x", DarkRP.getPhrase("arguments"), ""))
			return ""
		end
		local Employee = Player(tonumber(Args[1] or -1) or -1)
		local Raise = tonumber(Args[2])
		if not IsValid(Employee) or not Employee:IsPlayer() or not Raise then
			DarkRP.notify(ply, 1, 4, DarkRP.getPhrase("invalid_x", DarkRP.getPhrase("arguments"), ""))
			return ""
		end
		local Wage = Employee:GetEmploymentWage()
		local Employer = Employee:GetEmployer()
		if IsValid(Employer) then
			DarkRP.notify(Employer, 0, 8, "Your have increased the employment wage of "..Employee:Nick().." from $"..Wage.." to $"..(Wage + Raise))
		end
		DarkRP.notify(Employer, 0, 8, Employer:Nick().." has given you a raise! Your new wage is $"..(Wage + Raise).." it was $"..Wage)
		Employee:setDarkRPVar("EmploymentWage", Wage + Raise)
		return ""
	end)
	
	hook.Add("PlayerDisconnected", "Employment system", function(Ply)
		for _, v in pairs(player:GetAll()) do
			if v:GetEmployer() == Ply then
				EndEmployment(v, "Employer has left the server")
			end
		end
	end)

	hook.Add("OnPlayerChangedTeam", "Employment system", function(Ply, Prev, New)
		if Ply:IsEmployed() then
			EndEmployment(Ply, "Employee has changed team")
		end
	end)
	
	hook.Add("playerArrested", "Employment system", function(Ply)
		if Ply:IsEmployed() then
			EndEmployment(Ply, "Employee has been arrested")
		end
	end)
	
	hook.Add("PlayerDeath", "Employment system", function(Victim, Inflictor, Attacker)
		if Victim:GetEmployer() == Attacker then
			EndEmployment(Victim, "Employer has killed employee")
		elseif IsValid(Attacker) and Attacker:IsPlayer() and Attacker:GetEmployer() == Victim then
			EndEmployment(Attacker, "Employee has killed employer")
		end
	end)

	--[[function GM:PlayerDeath(Victim, Inflictor, Attacker)
		if Victim:GetEmployer() == Attacker then
			EndEmployment(Victim, "Employer has killed employee")
		elseif IsValid(Attacker) and Attacker:IsPlayer() and Attacker:GetEmployer() == Victim then
			EndEmployment(Attacker, "Employee has killed employer")
		end
	end]]
end

if CLIENT then
	surface.CreateFont("EMPLOYMENT_FONT_HUD", {
		font = "Roboto",
		size = 26,
		weight = 200,
		antialias = true
	})
	
	surface.CreateFont("EMPLOYMENT_FONT_LARGE", {
		font = "Roboto",
		size = 18,
		weight = 200,
		antialias = true
	})
	
	surface.CreateFont("EMPLOYMENT_FONT_MEDIUM", {
		font = "Roboto",
		size = 14,
		weight = 200,
		antialias = true
	})
	
	--[[hook.Add("HUDPaint", "DrawEmploymentTest", function()
		local Text = ""
		for _, v in pairs(player.GetAll()) do
			Text = Text..v:Nick()..":"..v:UserID()..":"..tostring(v:IsEmployed())..":"..tostring(v:GetEmployer())..":"..tostring(v:GetEmploymentWage()).."        "
		end
		surface.SetDrawColor(255, 255, 255)
		surface.DrawRect(ScrW() - 1005, ScrH() - 25, 1005, 25)
		surface.SetFont("EMPLOYMENT_FONT_LARGE")
		surface.SetTextColor(0, 0, 0)
		surface.SetTextPos(ScrW() - 1000, ScrH() - 20)
		surface.DrawText(Text)
	end)]]
	
	local localplayer = LocalPlayer()
	local HudText, TextCol1, TextCol2 = "Press E on me to send me an employment offer!", Color(255, 0, 0), Color(0, 0, 0, 200), Color(128, 30, 30, 255)
	hook.Add("HUDPaint", "DrawEmploymentOption", function()
		if not IsValid(localplayer) then
			localplayer = LocalPlayer()
			if not IsValid(localplayer) then
				return
			end
		end
		local x, y
		local Ply = localplayer:GetEyeTrace().Entity
		if IsValid(Ply) and Ply:IsPlayer() and Ply:IsEmployable() and not Ply:IsEmployed() and localplayer:GetPos():DistToSqr(Ply:GetPos()) < MinOfferDistanceSqr then
			x, y = ScrW()/2, ScrH()/2 + 30
			draw.DrawNonParsedText(HudText, "TargetID", x + 1, y + 1, TextCol1, 1)
			draw.DrawNonParsedText(HudText, "TargetID", x, y, TextCol2, 1)
		end
		
		if localplayer:IsEmployed() and IsValid(localplayer:GetEmployer()) then
			x, y = 40, 40
			local Text = "Employer: "..localplayer:GetEmployer():Nick().."  Wage: $"..tostring(localplayer:GetEmploymentWage())
			draw.DrawNonParsedText(Text, "EMPLOYMENT_FONT_HUD", x + 1, y + 1, TextCol1, 0)
			draw.DrawNonParsedText(Text, "EMPLOYMENT_FONT_HUD", x, y, TextCol2, 0)
		end
	end)
	
	hook.Add("PostPlayerDraw", "DrawEmploymentInfo", function(Ply)
		if not IsValid(localplayer) then
			localplayer = LocalPlayer()
			if not IsValid(localplayer) then
				return
			end
		end
		if not Ply:IsEmployed() then return end
		local Pos, Ang = Ply:GetShootPos(), localplayer:EyeAngles()
		Ang.p = 0
		Ang:RotateAroundAxis(Ang:Up(), -90)
		Ang:RotateAroundAxis(Ang:Forward(), 90)
		
		cam.Start3D2D(Pos, Ang, 0.3)
			local Text = "Employer: "..Ply:GetEmployer():Nick()
			draw.DrawNonParsedText(Text, "EMPLOYMENT_FONT_LARGE", 1, -100, TextCol1, 1)
			draw.DrawNonParsedText(Text, "EMPLOYMENT_FONT_LARGE", 0, -101, TextCol2, 1)
		cam.End3D2D()
	end)
	
	local OfferMenu
	local function OpenEmploymentOfferMenu(Employee)
		if OfferMenu and IsValid(OfferMenu) then
			OfferMenu:Remove()
		end
		OfferMenu = vgui.Create("DFrame")
		OfferMenu:SetSize(400, 200)
		OfferMenu:SetTitle("Employ player")
		OfferMenu:Center()
		OfferMenu:ShowCloseButton(true)
		OfferMenu:MakePopup()
		OfferMenu.lblTitle:SetFont("EMPLOYMENT_FONT_LARGE")
		OfferMenu.btnMaxim:SetVisible(false)
		OfferMenu.btnMinim:SetVisible(false)
		OfferMenu.btnClose.DoClick = function() OfferMenu:Close() end
		OfferMenu.btnClose.Paint = function(self, w, h)
			draw.RoundedBoxEx(8, 0, h * 0.1, w, h * 0.58, Color(220, 80, 80), false, true, true, false)
		end
		OfferMenu.Paint = function(self, w, h)
			draw.RoundedBoxEx(8, 0, 0, w, 24, Color(32, 178, 170), false, true, false, false)
			draw.RoundedBoxEx(8, 0, 24, w, h - 24, Color(245, 245, 245), false, false, true, false)
		end
		
		local PlayerIconParent = vgui.Create("Panel", OfferMenu)
		PlayerIconParent:SetWidth(200)
		PlayerIconParent:Dock(LEFT)
		
		local PlayerIcon = vgui.Create("DModelPanel", PlayerIconParent)
		PlayerIcon:SetSize(176, 120)
		PlayerIcon:Dock(FILL)
		PlayerIcon:DockMargin(30, 20, 30, 20)
		PlayerIcon:SetModel(Employee:GetModel())
		function PlayerIcon:LayoutEntity(Entity)
			Entity:SetSequence(Entity:LookupSequence("menu_combine"))
			return
		end
		local EyePos = PlayerIcon.Entity:GetBonePosition(PlayerIcon.Entity:LookupBone("ValveBiped.Bip01_Head1")) + Vector(0, 0, 2)
		PlayerIcon:SetLookAt(EyePos)
		PlayerIcon:SetCamPos(EyePos + Vector(15, 0, 0))
		PlayerIcon.Entity:SetEyeTarget(EyePos + Vector(15, 0, 0))
		
		local PlayerLabel = vgui.Create("Panel", OfferMenu)
		PlayerLabel:Dock(TOP)
		PlayerLabel:DockMargin(0, 20, 10, 10)
		PlayerLabel.Text = Employee:Nick().."  -  "..team.GetName(Employee:Team())
		PlayerLabel.Font = "EMPLOYMENT_FONT_MEDIUM"
		PlayerLabel.TextColor = Color(20, 20, 20)
		PlayerLabel.Paint = function(self, w, h)
			surface.SetDrawColor(120, 120, 120)
			surface.DrawRect(0, 0, w, h)
			
			surface.SetDrawColor(255, 255, 255)
			surface.DrawRect(1, 1, w - 2, h - 2)
			
			surface.SetFont(self.Font)
			surface.SetTextColor(self.TextColor)
			surface.SetTextPos(w/2 - surface.GetTextSize(self.Text)/2, 5)
			surface.DrawText(self.Text)
		end
		
		local SendButton = vgui.Create("DButton", OfferMenu)
		SendButton:Dock(BOTTOM)
		SendButton:DockMargin(0, 10, 10, 20)
		SendButton:SetText("Send offer")
		SendButton:SetFont("EMPLOYMENT_FONT_MEDIUM")
		SendButton.Paint = function(self, w, h)
			surface.SetDrawColor(120, 120, 120)
			surface.DrawRect(0, 0, w, h)
			
			surface.SetDrawColor(255, 255, 255)
			surface.DrawRect(1, 1, w - 2, h - 2)
		end
		
		local NumberParent = vgui.Create("Panel", OfferMenu)
		NumberParent:Dock(BOTTOM)
		NumberParent:DockMargin(0, 0, 10, 0)
		
		local Number = vgui.Create("DTextEntry", NumberParent)
		Number:Dock(FILL)
		surface.SetFont("EMPLOYMENT_FONT_MEDIUM")
		Number:DockMargin(surface.GetTextSize("Wage $") + 2, 0, 0, 0)
		Number:SetNumeric(true)
		Number:SetText(200)
		Number:SetFont("EMPLOYMENT_FONT_MEDIUM")
		Number.OnEnter = function()
			local CaretPos = Number:GetCaretPos()
			Number:SetText(Format("%i", math.min(math.max(tonumber(Number:GetText()) or 0, 20), 10000)))
			Number:SetCaretPos(CaretPos)
		end
		Number:SetPaintBackground(false)
		
		NumberParent.Paint = function(self, w, h)
			surface.SetDrawColor(120, 120, 120)
			surface.DrawRect(0, 0, w, h)
			
			surface.SetDrawColor(Number:HasFocus() and Color(255, 240, 180) or Color(255, 255, 255))
			surface.DrawRect(1, 1, w - 2, h - 2)
			
			surface.SetFont(Number:GetFont())
			surface.SetTextColor(Number:GetTextColor())
			surface.SetTextPos(5, 5)
			surface.DrawText("Wage $")
		end
		
		SendButton.DoClick = function()
			if IsValid(Employee) then
				RunConsoleCommand("darkrp", "offeremployment", Employee:UserID(), Number:GetText())
			end
			OfferMenu:Remove()
		end
	end
	
	local Menu
	local RedrawPlayerList
	local function OpenEmploymentMenu()
		if Menu and IsValid(Menu) then
			Menu:Remove()
		end
		Menu = vgui.Create("DFrame")
		Menu:SetSize(500, 500)
		Menu:SetTitle("Employed players")
		Menu:Center()
		Menu:ShowCloseButton(true)
		Menu:MakePopup()
		Menu.lblTitle:SetFont("EMPLOYMENT_FONT_LARGE")
		Menu.btnMaxim:SetVisible(false)
		Menu.btnMinim:SetVisible(false)
		Menu.btnClose.DoClick = function() Menu:Close() end
		Menu.btnClose.Paint = function(self, w, h)
			draw.RoundedBoxEx(8, 0, h * 0.1, w, h * 0.58, Color(220, 80, 80), false, true, true, false)
		end
		Menu.Paint = function(self, w, h)
			draw.RoundedBoxEx(8, 0, 0, w, 24, Color(32, 178, 170), false, true, false, false)
			draw.RoundedBoxEx(8, 0, 24, w, h - 24, Color(245, 245, 245), false, false, true, false)
		end
		
		local PlayerList = vgui.Create("DScrollPanel", Menu)
		PlayerList:Dock(FILL)
		
		local SBar = PlayerList:GetVBar()
		function SBar:Paint(w, h)
			surface.SetDrawColor(160, 160, 160)
			surface.DrawRect(0, 0, w, h)
		end
		function SBar.btnUp:Paint(w, h)
			surface.SetDrawColor(255, 255, 255)
			surface.DrawRect(2, 2, w - 4, h - 4)
		end
		function SBar.btnDown:Paint(w, h)
			surface.SetDrawColor(255, 255, 255)
			surface.DrawRect(2, 2, w - 4, h - 4)
		end
		function SBar.btnGrip:Paint(w, h)
			surface.SetDrawColor(255, 255, 255)
			surface.DrawRect(2, 0, w - 4, h)
		end
		
		function RedrawPlayerList()
			if not IsValid(PlayerList) then
				return
			end
			PlayerList:Clear()
			for i, s in pairs(player.GetAll()) do
				if s:GetEmployer() == LocalPlayer() then
					local Label = vgui.Create("Panel", PlayerList)
					Label:Dock(TOP)
					Label:DockMargin(5, 5, 5, 0)
					Label.Font = "EMPLOYMENT_FONT_MEDIUM"
					Label.TextColor = Color(0, 0, 0)
					Label.Text = "Employee: "..s:Nick().."   Wage: "..s:GetEmploymentWage()
					Label.Paint = function(self, w, h)
						draw.RoundedBoxEx(8, 0, 0, w, h, Color(120, 120, 120), false, true, true, false)
						draw.RoundedBoxEx(8, 1, 1, w * 0.8 - 2, h - 2, Color(255, 255, 255), false, true, true, false)
						
						surface.SetFont(self.Font)
						surface.SetTextColor(20, 20, 20)
						surface.SetTextPos(5, 5)
						surface.DrawText(self.Text)
					end
					local FireButton = vgui.Create("DButton", Label)
					FireButton:SetText("Fire")
					FireButton:SetFont("EMPLOYMENT_FONT_MEDIUM")
					FireButton:SetTextColor(Color(255, 200, 200))
					FireButton:Dock(RIGHT)
					FireButton.Paint = function(self, w, h)
						draw.RoundedBoxEx(8, 0, 1, w - 1, h - 2, Color(220, 80, 80), false, true, false, false)
					end
					FireButton.DoClick = function()
						RunConsoleCommand("darkrp", "fireemployee", s:UserID())
					end
					
					local Number
					local RaiseButton = vgui.Create("DButton", Label)
					RaiseButton:SetText("Give Raise")
					RaiseButton:SetFont("EMPLOYMENT_FONT_MEDIUM")
					RaiseButton:SetTextColor(Color(200, 255, 200))
					RaiseButton:Dock(RIGHT)
					RaiseButton.Paint = function(self, w, h)
						draw.RoundedBoxEx(8, 1, 1, w, h - 2, Color(80, 220, 80), false, false, true, false)
					end
					RaiseButton.DoClick = function()
						RunConsoleCommand("darkrp", "employeeraise", s:UserID(), Number:GetText())
					end
					
					local NumberParent = vgui.Create("Panel", Label)
					NumberParent:Dock(RIGHT)
					NumberParent:SetWide(120)
					
					Number = vgui.Create("DTextEntry", NumberParent)
					Number:Dock(FILL)
					surface.SetFont("EMPLOYMENT_FONT_MEDIUM")
					Number:DockMargin(surface.GetTextSize("Raise amount $") + 2, 0, 0, 0)
					Number:SetNumeric(true)
					Number:SetText(50)
					Number:SetFont("EMPLOYMENT_FONT_MEDIUM")
					Number.OnEnter = function()
						local CaretPos = Number:GetCaretPos()
						Number:SetText(Format("%i", math.min(math.max(tonumber(Number:GetText()) or 0, 20), 10000)))
						Number:SetCaretPos(CaretPos)
					end
					Number:SetPaintBackground(false)
					
					NumberParent.Paint = function(self, w, h)
						surface.SetDrawColor(120, 120, 120)
						surface.DrawRect(0, 0, w/2, h)
						
						surface.SetDrawColor(Number:HasFocus() and Color(255, 240, 180) or Color(255, 255, 255))
						surface.DrawRect(1, 1, w - 2, h - 2)
						
						surface.SetFont(Number:GetFont())
						surface.SetTextColor(Number:GetTextColor())
						surface.SetTextPos(5, 5)
						surface.DrawText("Raise amount $")
					end
					
					PlayerList:AddItem(Label)
				end
			end
		end
		RedrawPlayerList()
	end
	
	concommand.Add("employment", function()
		OpenEmploymentMenu()
	end)
	
	hook.Add("DarkRPVarChanged", "EmploymentStatusChange", function(Plr, VarName, OldValue, NewValue)
		if (VarName == "Employer" or VarName == "EmploymentWage") and RedrawPlayerList then
			timer.Simple(0, function()
				RedrawPlayerList()
			end)
		end
	end)
	
	local LastKeyPress = 0
	hook.Add("KeyPress", "OpenEmploymentOfferMenu", function(Plr, Key)
		if Key ~= IN_USE or LastKeyPress > CurTime() - 0.2 then return end
		LastKeyPress = CurTime()
		local Employee = Plr:GetEyeTrace().Entity
		
		if not IsValid(Employee) or not Employee:IsPlayer() or not Employee:IsEmployable() or Plr:GetPos():DistToSqr(Employee:GetPos()) > MinOfferDistanceSqr then return end
		
		local CanRequest, Message = hook.Call("CanOfferEmployment", DarkRP.hooks, Employee, Plr)
		
		if not CanRequest then
			return
		end
		
		OpenEmploymentOfferMenu(Employee)
	end)
end