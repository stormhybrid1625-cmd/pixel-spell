-- Health (remplace la régénération par défaut de Roblox)
-- Régénération NATURELLE : 1 % de la vie max par seconde. Les malus d'infusion (attributs RegenHpMult /
-- RegenHpUntil posés par WandServer.Combat) la ralentissent ou la bloquent. Les soins ne passent pas par ici.
local hum = script.Parent:WaitForChild("Humanoid")
local RATE = 0.01
local STEP = 0.5
while hum.Parent and hum.Health > 0 do
	task.wait(STEP)
	if hum.Health > 0 and hum.Health < hum.MaxHealth then
		local mult = 1
		if (hum:GetAttribute("RegenHpUntil") or 0) > workspace:GetServerTimeNow() then
			mult = hum:GetAttribute("RegenHpMult") or 1
		end
		if mult > 0 then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * RATE * STEP * mult)
		end
	end
end
