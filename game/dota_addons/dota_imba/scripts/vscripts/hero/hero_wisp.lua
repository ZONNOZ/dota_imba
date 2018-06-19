-- Copyright (C) 2018  The Dota IMBA Development Team
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Editors:
--     EarthSalamander #42, 23.05.2018
--	   Naowin, 13.06.2018
--     Based on old Dota 2 Spell Library: https://github.com/Pizzalol/SpellLibrary/blob/master/game/scripts/vscripts/heroes/hero_wisp

CreateEmptyTalents("wisp")

------------------------------
--			TETHER			--
------------------------------
imba_wisp_tether = class({})
LinkLuaModifier("modifier_imba_wisp_tether", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_tether_ally", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_tether_latch", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_tether_slow", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_tether_slow_immune", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_tether_ally_attack", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)

function imba_wisp_tether:GetCustomCastErrorTarget(target)
	if target == self:GetCaster() then
		return "dota_hud_error_cant_cast_on_self"
	end
end

function imba_wisp_tether:CastFilterResultTarget(target)
	if IsServer() then
		local caster = self:GetCaster()
		local casterID = caster:GetPlayerOwnerID()
		local targetID = target:GetPlayerOwnerID()
		if target == caster then
			return UF_FAIL_CUSTOM
		end

		if target ~= nil and not target:IsOpposingTeam(caster:GetTeamNumber()) and PlayerResource:IsDisableHelpSetForPlayerID(targetID,casterID) then
			return UF_FAIL_DISABLE_HELP
		end

		local nResult = UnitFilter(target, self:GetAbilityTargetTeam(), self:GetAbilityTargetType(), self:GetAbilityTargetFlags(), caster:GetTeamNumber())
		return nResult
	end
end

function imba_wisp_tether:OnSpellStart()
	local ability 			= self:GetCaster():FindAbilityByName("imba_wisp_tether")
	local ability_level 	= ability:GetLevel() -1
	local caster 			= self:GetCaster()
	local movespeed 		= ability:GetLevelSpecialValueFor("movespeed", ability_level)
	ability.slow_duration 	= ability:GetLevelSpecialValueFor("stun_duration", ability_level)
	ability.slow 	    	= ability:GetSpecialValueFor("slow")

	self.caster_origin 		= self:GetCaster():GetAbsOrigin()
	self.target_origin 		= self:GetCursorTarget():GetAbsOrigin()
	self.tether_ally 		= self:GetCursorTarget()
	self.tether_slowedUnits = {}

	caster.tether_lastHealth 	= caster:GetHealth()
	caster.tether_lastMana 		= caster:GetMana()

	self.target = self:GetCursorTarget()
	caster:AddNewModifier(self:GetCaster(), self, "modifier_imba_wisp_tether", {})
	local tether_modifier = self:GetCursorTarget():AddNewModifier(self:GetCaster(), ability, "modifier_imba_wisp_tether_ally", {})
	tether_modifier:SetStackCount(movespeed)

	if caster:HasModifier("modifier_imba_wisp_overcharge") then
		imba_wisp_overcharge:AddOvercharge(self:GetCaster(), self.target)
	end

	if caster:HasTalent("special_bonus_imba_wisp_4") then
		self.tether_ally:SetStolenScepter(true)
	end

	if caster:HasTalent("special_bonus_imba_wisp_6") then
		self.target:AddNewModifier(self:GetCaster(), ability, "modifier_imba_wisp_tether_ally_attack", {})
	end

	local distToAlly = (self:GetCursorTarget():GetAbsOrigin() - caster:GetAbsOrigin()):Length2D()
	if distToAlly >= self:GetSpecialValueFor("latch_distance") then
		caster:AddNewModifier(caster, self, "modifier_imba_wisp_tether_latch", {})
	end

	caster:SwapAbilities("imba_wisp_tether", "imba_wisp_tether_break", false, true)
	caster:FindAbilityByName("imba_wisp_tether_break"):SetLevel(1)
end

modifier_imba_wisp_tether = class({})
function modifier_imba_wisp_tether:IsHidden() return false end
function modifier_imba_wisp_tether:IsPurgable() return false end

function modifier_imba_wisp_tether:OnCreated(params)
	if IsServer() then 
		self.target 			= self:GetAbility().target
		self.radius 			= self:GetAbility():GetSpecialValueFor("radius")
		self.tether_heal_amp 	= self:GetAbility():GetSpecialValueFor("tether_heal_amp")
		EmitSoundOn("Hero_Wisp.Tether", self:GetParent())
		self:StartIntervalThink(FrameTime())
	end
end

function modifier_imba_wisp_tether:DeclareFunctions()
	local decFuncs = {
		MODIFIER_EVENT_ON_TAKEDAMAGE,
		MODIFIER_EVENT_ON_HEALTH_GAINED,
		MODIFIER_EVENT_ON_MANA_GAINED,
		MODIFIER_EVENT_ON_SPENT_MANA,
		MODIFIER_PROPERTY_MOVESPEED_ABSOLUTE_MIN,
	}

	return decFuncs
end

function modifier_imba_wisp_tether:OnIntervalThink()
	if IsServer() then
		self:GetParent().tether_lastHealth = self:GetParent():GetHealth()

		CustomNetTables:SetTableValue(
		"player_table", 
		tostring(self:GetCaster():GetPlayerOwnerID()), 
		{ 	
			tether_movement_speed = self:GetAbility().tether_ally:GetIdealSpeed()
		})

		if self:GetParent():HasModifier("modifier_imba_wisp_tether_latch") then
			return
		end

		local distance = (self:GetAbility().tether_ally:GetAbsOrigin() - self:GetParent():GetAbsOrigin()):Length2D()

		if distance <= self.radius then
			return
		end

		self:GetParent():RemoveModifierByName("modifier_imba_wisp_tether")
	end
end

function modifier_imba_wisp_tether:OnTakeDamage(keys)
	if keys.unit == self:GetParent() then
		self:GetCaster().tether_lastHealth = self:GetCaster():GetHealth()
	end
end

function modifier_imba_wisp_tether:OnSpentMana(keys)
	if keys.unit == self:GetParent() then
		self:GetCaster().tether_lastMana = self:GetCaster():GetMana()
	end
end

function modifier_imba_wisp_tether:OnHealthGained(keys)
	if keys.unit == self:GetParent() then
		local healthGained = self:GetCaster():GetHealth() - self:GetCaster().tether_lastHealth

		if healthGained > 0 then
			--print("Health gained:", healthGained, self:GetAbility():GetCaster().tether_lastHealth)

			self.target:Heal(healthGained * self.tether_heal_amp, self:GetAbility())
			self:GetCaster().tether_lastHealth = self:GetCaster():GetHealth()
			SendOverheadEventMessage(nil, OVERHEAD_ALERT_HEAL, self.target, healthGained * self.tether_heal_amp, nil)
				
		end
	end
end

function modifier_imba_wisp_tether:OnManaGained(keys)
	if keys.unit == self:GetParent() then
		local manaGained = self:GetCaster():GetMana() - self:GetCaster().tether_lastMana

		if manaGained > 0 then
			--print(manaGained, self:GetCaster().tether_lastMana)

			self.target:GiveMana(manaGained * self.tether_heal_amp)
			self:GetCaster().tether_lastMana = self:GetCaster():GetMana()
			SendOverheadEventMessage(nil, OVERHEAD_ALERT_MANA_ADD, self.target, manaGained * self.tether_heal_amp, nil)
		end
	end
end

function modifier_imba_wisp_tether:GetModifierMoveSpeed_AbsoluteMin()
    local net_table = CustomNetTables:GetTableValue("player_table", tostring(self:GetCaster():GetPlayerOwnerID())) or {}
	return net_table.tether_movement_speed or 0
end

function modifier_imba_wisp_tether:OnRemoved()
	if IsServer() then
		if self:GetParent():HasModifier("modifier_imba_wisp_tether_latch") then
			self:GetParent():RemoveModifierByName("modifier_imba_wisp_tether_latch")
		end

		if self.target:HasModifier("modifier_imba_wisp_tether_ally") then
			self.target:RemoveModifierByName("modifier_imba_wisp_overcharge")
			self.target:RemoveModifierByName("modifier_imba_wisp_tether_ally")
		end

		if self:GetCaster():HasTalent("special_bonus_imba_wisp_4") then
			self.target:SetStolenScepter(false)
		end

		self:GetCaster():EmitSound("Hero_Wisp.Tether.Stop")
		self:GetCaster():StopSound("Hero_Wisp.Tether")
		self:GetParent():SwapAbilities("imba_wisp_tether_break", "imba_wisp_tether", false, true)
	end
end


------------------------------
--	 TETHER AllY modifier	--
------------------------------
modifier_imba_wisp_tether_ally = class({})
function modifier_imba_wisp_tether_ally:IsHidden() return false end
function modifier_imba_wisp_tether_ally:IsPurgable() return false end
function modifier_imba_wisp_tether_ally:DeclareFunctions()
	local decFuncs = {
		MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE
	}

	return decFuncs
end

function modifier_imba_wisp_tether_ally:OnCreated()
	if IsServer() then
		self.pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_tether.vpcf", PATTACH_ABSORIGIN_FOLLOW, self:GetParent())
		ParticleManager:SetParticleControlEnt(self.pfx, 0, self:GetCaster(), PATTACH_POINT_FOLLOW, "attach_hitloc", self:GetCaster():GetAbsOrigin(), true)
		ParticleManager:SetParticleControlEnt(self.pfx, 1, self:GetParent(), PATTACH_POINT_FOLLOW, "attach_hitloc", self:GetParent():GetAbsOrigin(), true)

		self:StartIntervalThink(FrameTime())
		EmitSoundOn("Hero_Wisp.Tether.Target", self:GetParent())

		if self:GetCaster():HasTalent("special_bonus_imba_wisp_8") then
			local movement_speed_cap = self:GetCaster():FindTalentValue("special_bonus_imba_wisp_8", "movement_speed_cap")

			CustomNetTables:SetTableValue(
			"player_table", 
			tostring(self:GetCaster():GetPlayerOwnerID()), 
			{ 	
				tether_limit 			= movement_speed_cap,
				tether_minimum_speed 	= self:GetParent():GetIdealSpeed(),
			})

			self:GetParent():AddNewModifier(
				self:GetCaster(), 
				self, 
				"modifier_imba_wisp_tether_slow_immune", 
				{
					limit 			= movement_speed_cap,
					minimum_speed 	= self:GetParent():GetIdealSpeed()
				})

			self:GetCaster():AddNewModifier(
				self:GetCaster(), 
				self, 
				"modifier_imba_wisp_tether_slow_immune", 
				{
					limit 			= movement_speed_cap,
					minimum_speed 	= self:GetParent():GetIdealSpeed()
				})
		end
	end
end

function modifier_imba_wisp_tether_ally:OnIntervalThink()
	if IsServer() then
		local velocity = self:GetParent():GetAbsOrigin() - self:GetCaster():GetAbsOrigin()
		local vVelocity = velocity / FrameTime()
		vVelocity.z = 0

		local projectile = 
		{
			Ability				= self:GetAbility(),
			EffectName			= "particles/hero/ghost_revenant/blackjack_projectile.vpcf",
			vSpawnOrigin		= self:GetCaster():GetAbsOrigin(),
			fDistance			= velocity:Length2D(),
			fStartRadius		= 100,
			fEndRadius			= 100,
			bReplaceExisting 	= false,
			iMoveSpeed			= vVelocity,
			Source				= self:GetCaster(),
			iUnitTargetTeam		= DOTA_UNIT_TARGET_TEAM_ENEMY,
			iUnitTargetFlags	= DOTA_UNIT_TARGET_FLAG_NONE,
			iUnitTargetType		= DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
			fExpireTime			= GameRules:GetGameTime() + 1,
			bDeleteOnHit		= false,
			vVelocity			= vVelocity / 3, 
			ExtraData 			= {
				slow_duration 	= self:GetAbility().slow_duration,
				slow 			= self:GetAbility().slow
			}
		}

		ProjectileManager:CreateLinearProjectile(projectile)
	end
end

function modifier_imba_wisp_tether_ally:GetModifierMoveSpeedBonus_Percentage()
	return self:GetStackCount()
end

function imba_wisp_tether:OnProjectileHit_ExtraData(target, location, ExtraData)
	if target ~= nil then
		-- Variables
		local caster		= self:GetCaster()
		local slow 			= ExtraData.slow
		local slow_duration = ExtraData.slow_duration

		-- Already got slowed
		--if self:GetAbility().tether_slowedUnits[target] then
		--	return
		--end

		-- Apply slow debuff
		local slow_ref = target:AddNewModifier(caster, self, "modifier_imba_wisp_tether_slow", { duration = slow_duration })
		slow_ref:SetStackCount(slow)

		-- An enemy unit may only be slowed once per cast.
		-- We store the enemy unit to the hashset, so we can check whether the unit has got debuff already later on.
		--self:GetAbility().tether_slowedUnits[target] = true
	end
end

function modifier_imba_wisp_tether_ally:GetModifierMoveSpeedBonus_Percentage()
	return self:GetAbility():GetSpecialValueFor("movespeed")
end

function modifier_imba_wisp_tether_ally:OnRemoved() 
	if IsServer() then
		self:GetParent():RemoveModifierByName("modifier_imba_wisp_tether_slow_immune")
		self:GetCaster():RemoveModifierByName("modifier_imba_wisp_tether_slow_immune")
		self:GetParent():RemoveModifierByName("modifier_imba_wisp_tether_ally_attack")
		self:GetCaster():RemoveModifierByName("modifier_imba_wisp_tether")
		self:GetParent():StopSound("Hero_Wisp.Tether.Target")
		ParticleManager:DestroyParticle(self.pfx, false)
		ParticleManager:ReleaseParticleIndex(self.pfx)
	end
end

--------------------------------------
--	 TETHER Track attack modifier	--
--------------------------------------
modifier_imba_wisp_tether_ally_attack = class({})
function modifier_imba_wisp_tether_ally_attack:IsHidden() return false end
function modifier_imba_wisp_tether_ally_attack:DeclareFunctions()
	local decFuncs = {
		MODIFIER_EVENT_ON_ATTACK
	}

	return decFuncs
end

function modifier_imba_wisp_tether_ally_attack:OnAttack(params)
	if IsServer() then
		if params.attacker == self:GetParent() then
			self:GetCaster():PerformAttack(params.target, true, true, true, false, true, false, false)
		end
	end
end

--------------------------------------
--	 TETHER slow immune modifier	--
--------------------------------------
modifier_imba_wisp_tether_slow_immune = class({})
function modifier_imba_wisp_tether_slow_immune:IsHidden() return true end
function modifier_imba_wisp_tether_slow_immune:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_MOVESPEED_ABSOLUTE_MIN,
		MODIFIER_PROPERTY_MOVESPEED_LIMIT
	}
	return funcs
end

function modifier_imba_wisp_tether_slow_immune:OnCreated(params)
	if IsServer() then 
		self.limit 			= params.limit
		self.minimum_speed 	= params.minimum_speed
	else
		local net_table 	= CustomNetTables:GetTableValue("player_table", tostring(self:GetCaster():GetPlayerOwnerID())) or {}
		self.minimum_speed 	= net_table.tether_minimum_speed or 0
		self.limit 			= net_table.tether_limit or 0
	end
end

function modifier_imba_wisp_tether_slow_immune:GetModifierMoveSpeed_AbsoluteMin()
	return self.minimum_speed
end

function modifier_imba_wisp_tether_slow_immune:GetModifierMoveSpeed_Limit()
	return self.limit
end

------------------------------
--	 TETHER slow modifier	--
------------------------------
modifier_imba_wisp_tether_slow = class({})
function modifier_imba_wisp_tether_slow:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_MOVESPEED_BONUS_CONSTANT,
		MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT
	}	
	return funcs
end

function modifier_imba_wisp_tether_slow:GetModifierMoveSpeedBonus_Constant()
	return self:GetStackCount()
end

function modifier_imba_wisp_tether_slow:GetModifierAttackSpeedBonus_Constant()
	return self:GetStackCount()
end

function modifier_imba_wisp_tether_slow:OnCreated()
end


------------------------------
--	 TETHER latch modifier	--
------------------------------
modifier_imba_wisp_tether_latch = class({})
function modifier_imba_wisp_tether_latch:OnCreated()
	if IsServer() then
		self.target = self:GetAbility().target
		self:StartIntervalThink(FrameTime())
	end
end

function modifier_imba_wisp_tether_latch:OnIntervalThink()
	if IsServer() then
		-- Calculate the distance
		local casterDir = self:GetCaster():GetAbsOrigin() - self.target:GetAbsOrigin()
		local distToAlly = casterDir:Length2D()
		casterDir = casterDir:Normalized()

		if distToAlly > self:GetAbility():GetSpecialValueFor("latch_distance") then
			-- Leap to the target
			distToAlly = distToAlly - self:GetAbility():GetSpecialValueFor("latch_speed") * FrameTime()
			distToAlly = math.max( distToAlly, self:GetAbility():GetSpecialValueFor("latch_distance"))	-- Clamp this value

			local pos = self.target:GetAbsOrigin() + casterDir * distToAlly
			pos = GetGroundPosition(pos, self:GetCaster())

			self:GetCaster():SetAbsOrigin(pos)
		end

		if distToAlly <= self:GetAbility():GetSpecialValueFor("latch_distance") then
			-- We've reached, so finish latching
			ResolveNPCPositions(self:GetCaster():GetAbsOrigin(), 128)
			self:GetCaster():RemoveModifierByName("modifier_imba_wisp_tether_latch")
		end
	end
end

------------------------------
--		 BREAK TETHER 		--
------------------------------
imba_wisp_tether_break = class({})
function imba_wisp_tether_break:IsInnateAbility() return true end

function imba_wisp_tether_break:OnSpellStart()
	self:GetCaster():RemoveModifierByName("modifier_imba_wisp_tether")
	local target = self:GetCaster():FindAbilityByName("imba_wisp_tether").target
	if target ~= nil and target:HasModifier("modifier_imba_wisp_overcharge") then
		target:RemoveModifierByName("modifier_imba_wisp_overcharge")
	end
end

------------------------------
--			SPIRITS			--
------------------------------
imba_wisp_spirits = class({})
LinkLuaModifier("modifier_imba_wisp_spirits", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_spirit_handler", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_spirits_hero_hit", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_spirits_creep_hit", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_spirits_slow", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
function imba_wisp_spirits:OnSpellStart()
	if IsServer() then
		self.caster 					= self:GetCaster()
		self.ability 					= self.caster:FindAbilityByName("imba_wisp_spirits")
		self.start_time 				= GameRules:GetGameTime()
		self.spirits_num_spirits		= 0
		local ability_level 			= self.ability:GetLevel() - 1
		local spirit_min_radius 		= self.ability:GetLevelSpecialValueFor("min_range", ability_level)
		local spirit_max_radius 		= self.ability:GetLevelSpecialValueFor("max_range", ability_level)
		local spirit_movement_rate		= self.ability:GetLevelSpecialValueFor("spirit_movement_rate", ability_level)
		local creep_damage				= self.ability:GetLevelSpecialValueFor("creep_damage", ability_level)
		local hero_damage				= self.ability:GetLevelSpecialValueFor("hero_damage", ability_level)
		local explosion_damage			= self.ability:GetLevelSpecialValueFor("explosion_damage", ability_level)
		local slow						= self.ability:GetLevelSpecialValueFor("slow", ability_level)
		local spirit_duration 			= self.ability:GetLevelSpecialValueFor("spirit_duration", ability_level)
		local spirit_summon_interval	= self.ability:GetSpecialValueFor("spirit_summon_interval")
		local max_spirits 				= self.ability:GetSpecialValueFor("num_spirits")
		local collision_radius			= self.ability:GetSpecialValueFor("collision_radius")
		local explosion_radius			= self.ability:GetSpecialValueFor("explode_radius")
		local spirit_turn_rate 			= self.ability:GetSpecialValueFor("spirit_turn_rate")
		local vision_radius				= self.ability:GetSpecialValueFor("explode_radius")
		local vision_duration 			= self.ability:GetSpecialValueFor("vision_duration")
		local slow_duration 			= self.ability:GetSpecialValueFor("slow_duration")

		if self.caster:HasTalent("special_bonus_imba_wisp_1") then
			local additional_spirits = self.caster:FindTalentValue("special_bonus_imba_wisp_1", "bonus_spirits")
			max_spirits = max_spirits + additional_spirits
		end

		if self.caster:HasTalent("special_bonus_imba_wisp_2") then
			local explosion_damage_pct = self.caster:FindTalentValue("special_bonus_imba_wisp_2", "bonus_explosion_damage_pct")
			explosion_damage = explosion_damage * explosion_damage_pct
		end

		self.spirits_movementFactor				= 1	
		self.ability.spirits_spiritsSpawned		= {}

		EmitSoundOn("Hero_Wisp.Spirits.Cast", self.caster)	

		self.caster:SwapAbilities("imba_wisp_spirits", "imba_wisp_spirits_toggle", false, true )
		self.caster:FindAbilityByName("imba_wisp_spirits_toggle"):SetLevel(1)
		self.caster:AddNewModifier(
			self.caster, 
			self.ability, 
			"modifier_imba_wisp_spirits", 
			{
				duration = spirit_duration,
				spirits_starttime 		= GameRules:GetGameTime(),
				spirit_summon_interval	= spirit_summon_interval,
				max_spirits 			= max_spirits,
				collision_radius 		= collision_radius,
				explosion_radius 		= explosion_radius,
				spirit_min_radius		= spirit_min_radius,
				spirit_max_radius		= spirit_max_radius,
				spirit_movement_rate	= spirit_movement_rate,
				spirit_turn_rate 		= spirit_turn_rate,
				vision_radius			= vision_radius,
				vision_duration			= vision_duration,
				creep_damage 			= creep_damage,
				hero_damage				= hero_damage,
				explosion_damage 		= explosion_damage,
				slow_duration 			= slow_duration,
				slow 					= slow
			}) 
	end
end

------------------------------
--		SPIRITS	modifier	--
------------------------------
modifier_imba_wisp_spirits = class({})
function modifier_imba_wisp_spirits:OnCreated(params)
	if IsServer() then
		self.start_time 				= params.spirits_starttime
		self.spirit_summon_interval 	= params.spirit_summon_interval
		self.max_spirits				= params.max_spirits
		self.collision_radius			= params.collision_radius
		self.explosion_radius			= params.explosion_radius
		self.spirit_radius 				= params.collision_radius
		self.spirit_min_radius			= params.spirit_min_radius
		self.spirit_max_radius			= params.spirit_max_radius
		self.spirit_movement_rate 		= params.spirit_movement_rate
		self.spirit_turn_rate			= params.spirit_turn_rate
		self.vision_radius				= params.vision_radius
		self.vision_duration			= params.vision_duration
		self.creep_damage 				= params.creep_damage * FrameTime()
		self.hero_damage				= params.hero_damage
		self.explosion_damage			= params.explosion_damage
		self.slow_duration				= params.slow_duration
		self.slow 						= params.slow

		if self:GetCaster():HasModifier("modifier_imba_wisp_swap_spirits_disarm") then
			self.particle = "particles/units/heroes/hero_wisp/wisp_guardian_disarm.vpcf"
			self:GetAbility():GetCaster().spirit_debuff = 1
		elseif self:GetCaster():HasModifier("modifier_imba_wisp_swap_spirits_silence") then
			self.particle = "particles/units/heroes/hero_wisp/wisp_guardian_silence.vpcf"
			self:GetAbility():GetCaster().spirit_debuff = 0
		end

		EmitSoundOn("Hero_Wisp.Spirits.Loop", self:GetCaster())	

		self:StartIntervalThink(0.03)
	end
end

function modifier_imba_wisp_spirits:OnIntervalThink()
	if IsServer() then
		local caster 					= self:GetCaster()
		local caster_position 			= caster:GetAbsOrigin()
		local ability 					= self:GetAbility()
		local elapsedTime 				= GameRules:GetGameTime() - self.start_time
		local idealNumSpiritsSpawned 	= elapsedTime / self.spirit_summon_interval

		idealNumSpiritsSpawned 			= math.min(idealNumSpiritsSpawned, self.max_spirits)

		if ability.spirits_num_spirits < idealNumSpiritsSpawned then

			-- Spawn a new spirit
			local newSpirit = CreateUnitByName("npc_dota_wisp_spirit", caster_position, false, caster, caster, caster:GetTeam())

			if caster:HasScepter() then
				newSpirit:SetDayTimeVisionRange(300)
				newSpirit:SetNightTimeVisionRange(300)
			end

			-- Create particle FX
			local pfx = ParticleManager:CreateParticle(self.particle, PATTACH_ABSORIGIN_FOLLOW, newSpirit)
			newSpirit.spirit_pfx = pfx

			-- Update the state
			local spiritIndex = ability.spirits_num_spirits + 1
			newSpirit.spirit_index = spiritIndex
			ability.spirits_num_spirits = spiritIndex
			ability.spirits_spiritsSpawned[spiritIndex] = newSpirit

			-- Apply the spirit modifier
			newSpirit:AddNewModifier(
				caster, 
				ability, 
				"modifier_imba_wisp_spirit_handler", 
				{ 
					duraiton 			= -1,
					vision_radius 		= self.vision_radius,
					vision_duration 	= self.vision_duration
				}
			)
		end

		--------------------------------------------------------------------------------
		-- Update the radius
		--
		local currentRadius	= self.spirit_radius
		local deltaRadius = ability.spirits_movementFactor * self.spirit_movement_rate * 0.03
		currentRadius = currentRadius + deltaRadius
		currentRadius = math.min( math.max( currentRadius, self.spirit_min_radius ), self.spirit_max_radius )

		self.spirit_radius = currentRadius

		--------------------------------------------------------------------------------
		-- Update the spirits' positions
		--
		local currentRotationAngle	= elapsedTime * self.spirit_turn_rate
		local rotationAngleOffset	= 360 / self.max_spirits

		local numSpiritsAlive = 0
		local updated_spirit_array = {}

		for k,spirit in pairs( ability.spirits_spiritsSpawned ) do
			numSpiritsAlive = numSpiritsAlive + 1
			local add_spirit = true

			-- Rotate
			local rotationAngle = currentRotationAngle - rotationAngleOffset * (k - 1)
			local relPos = Vector(0, currentRadius, 0)
			relPos = RotatePosition(Vector(0,0,0), QAngle( 0, -rotationAngle, 0 ), relPos)
			local absPos = GetGroundPosition( relPos + caster_position, spirit)

			spirit:SetAbsOrigin(absPos)

			-- Update particle
			ParticleManager:SetParticleControl(spirit.spirit_pfx, 1, Vector(currentRadius, 0, 0))

			-- Check if we hit stuff
			local nearby_enemy_units = FindUnitsInRadius(
				caster:GetTeam(),
				absPos, 
				nil, 
				self.collision_radius, 
				DOTA_UNIT_TARGET_TEAM_ENEMY,
				DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, 
				DOTA_UNIT_TARGET_FLAG_NONE, 
				FIND_ANY_ORDER, 
				false
			)

			if nearby_enemy_units ~= nil and #nearby_enemy_units > 0 then
				if modifier_imba_wisp_spirits:OnHit(caster, spirit, nearby_enemy_units, self.creep_damage, self.hero_damage, ability, self.slow_duration, self.slow) then 
					modifier_imba_wisp_spirits:Explode(caster, spirit, self.explosion_radius, self.explosion_damage, ability)
					spirit:RemoveModifierByName("modifier_imba_wisp_spirit_handler")
					add_spirit = false
				end
			end

			if add_spirit then
				updated_spirit_array[spirit.spirit_index] = spirit
			end
		end

		ability.spirits_spiritsSpawned = updated_spirit_array

		if ability.spirits_num_spirits == self.max_spirits and numSpiritsAlive == 0 then
			-- All spirits have been exploded.
			caster:RemoveModifierByName("modifier_imba_wisp_spirits")
			return
		end
	end
end

function modifier_imba_wisp_spirits:OnHit(caster, spirit, enemies_hit, creep_damage, hero_damage, ability, slow_duration, slow) 
	local hit_hero = false

	-- Deal damage to each enemy hero
	for _,enemy in pairs(enemies_hit) do
		-- cant dmg ded stuff
		if enemy:IsAlive() then 
			-- Initialize damage table
			local damage_table 			= {}
			damage_table.attacker 		= caster
			damage_table.ability 		= ability
			damage_table.damage_type 	= ability:GetAbilityDamageType() 
			damage_table.victim = enemy
			if enemy:IsHero() then
				enemy:AddNewModifier(caster, ability, "modifier_imba_wisp_spirits_hero_hit", {duration = 0.03, slow_duration = slow_duration, slow = slow})
				damage_table.damage	= hero_damage

				if caster.spirit_debuff == 1 then
					enemy:AddNewModifier(caster, ability, "modifier_disarmed", {duration=ability:GetSpecialValueFor("spirit_debuff_duration")})
				else
					enemy:AddNewModifier(caster, ability, "modifier_silence", {duration=ability:GetSpecialValueFor("spirit_debuff_duration")})
				end

				hit_hero = true
			else
				enemy:AddNewModifier(caster, ability, "modifier_imba_wisp_spirits_creep_hit", {duration = 0.03})
				damage_table.damage	= creep_damage
			end

			if caster == nil or spirit == nil or damage_table.attacker == nil or damage_table.ability == nil or damage_table.damage_type == nil or damage_table.damage == nil then
				for x,y in pairs(damage_table) do
					print(x)
					print(y)
				end
			end

			ApplyDamage(damage_table)
		end
	end

	if hit_hero then 
		return true
	else
		return false
	end
end

function modifier_imba_wisp_spirits:Explode(caster, spirit, explosion_radius, explosion_damage, ability)
	EmitSoundOn("Hero_Wisp.Spirits.Target", spirit)
	ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_guardian_explosion.vpcf", PATTACH_ABSORIGIN_FOLLOW, spirit)

	-- Check if we hit stuff
	local nearby_enemy_units = FindUnitsInRadius(
		caster:GetTeam(),
		spirit:GetAbsOrigin(), 
		nil, 
		explosion_radius, 
		DOTA_UNIT_TARGET_TEAM_ENEMY,
		DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, 
		DOTA_UNIT_TARGET_FLAG_NONE, 
		FIND_ANY_ORDER, 
		false
	)

	local damage_table 			= {}
	damage_table.attacker 		= caster
	damage_table.ability 		= ability
	damage_table.damage_type 	= ability:GetAbilityDamageType() 
	damage_table.damage			= explosion_damage

	-- Deal damage to each enemy hero
	for _,enemy in pairs(nearby_enemy_units) do
		damage_table.victim = enemy
		ApplyDamage(damage_table)
	end
end

function modifier_imba_wisp_spirits:OnRemoved()
	if IsServer() then
		self:GetCaster():SwapAbilities("imba_wisp_spirits_toggle", "imba_wisp_spirits", false, true )
		local ability 	= self:GetAbility()
		local caster 	= self:GetCaster()
		for k,spirit in pairs( ability.spirits_spiritsSpawned ) do
			if not spirit:IsNull() then
				modifier_imba_wisp_spirits:Explode(caster, spirit, self.explosion_radius, self.explosion_damage, ability)
				spirit:RemoveModifierByName("modifier_imba_wisp_spirit_handler")
			end
		end

		self:GetCaster():StopSound("Hero_Wisp.Spirits.Loop")
	end
end


----------------------------------------------------------------------
--		SPIRITS	on creep hit modifier 								--
----------------------------------------------------------------------
modifier_imba_wisp_spirits_creep_hit = class({})
function modifier_imba_wisp_spirits_creep_hit:IsHidden() return true end
function modifier_imba_wisp_spirits_creep_hit:OnCreated() 
	if IsServer() then
		local target = self:GetParent()
		EmitSoundOn("Hero_Wisp.Spirits.TargetCreep", target)
		self.pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_guardian_explosion_small.vpcf", PATTACH_ABSORIGIN_FOLLOW, target)
	end
end

function modifier_imba_wisp_spirits_creep_hit:OnRemoved()
	if IsServer() then
		ParticleManager:DestroyParticle(self.pfx, false)
	end
end

----------------------------------------------------------------------
--		SPIRITS	on hero hit modifier 								--
----------------------------------------------------------------------
modifier_imba_wisp_spirits_hero_hit = class({})
function modifier_imba_wisp_spirits_hero_hit:IsHidden() return true end
function modifier_imba_wisp_spirits_hero_hit:OnCreated(params) 
	if IsServer() then
		local target = self:GetParent()
		local slow_modifier = target:AddNewModifier(self:GetCaster(), self:GetAbility(), "modifier_imba_wisp_spirits_slow", {duration = params.slow_duration})
		slow_modifier:SetStackCount(params.slow)
	end
end

----------------------------------------------------------------------
--		SPIRITS	on hero hit slow modifier							--
----------------------------------------------------------------------
modifier_imba_wisp_spirits_slow = class({})
function modifier_imba_wisp_spirits_slow:IsDebuff() return true end
function modifier_imba_wisp_spirits_slow:IsHidden() return true end
function modifier_imba_wisp_spirits_slow:DeclareFunctions()
	local funcs = {MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
		MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT}
	return funcs
end

function modifier_imba_wisp_spirits_slow:GetModifierMoveSpeedBonus_Percentage()
	return self:GetStackCount()
end

function modifier_imba_wisp_spirits_slow:GetModifierAttackSpeedBonus_Constant()
	return self:GetStackCount()
end

----------------------------------------------------------------------
--		SPIRITS	modifier (keep them from getting targeted)			--
----------------------------------------------------------------------
modifier_imba_wisp_spirit_handler = class({})
function modifier_imba_wisp_spirit_handler:CheckState()
	local state = {
		[MODIFIER_STATE_NO_TEAM_MOVE_TO] 	= true,
		[MODIFIER_STATE_NO_TEAM_SELECT] 	= true,
		[MODIFIER_STATE_COMMAND_RESTRICTED] = true,
		[MODIFIER_STATE_ATTACK_IMMUNE] 		= true,
		[MODIFIER_STATE_MAGIC_IMMUNE] 		= true,
		[MODIFIER_STATE_INVULNERABLE] 		= true,
		[MODIFIER_STATE_UNSELECTABLE] 		= true,
		[MODIFIER_STATE_NO_HEALTH_BAR] 		= true,
	}

	if self:GetCaster():HasScepter() then
		state[MODIFIER_STATE_FLYING] = true
	end

	return state
end

function modifier_imba_wisp_spirit_handler:OnCreated(params)
	if IsServer() then
		self.vision_radius 		= params.vision_radius
		self.vision_duration	= params.vision_duration
	end
end

function modifier_imba_wisp_spirit_handler:OnDestroy()
	if IsServer() then
		local spirit	= self:GetParent()
		local ability	= self:GetAbility()

		ParticleManager:DestroyParticle(spirit.spirit_pfx, false)

		-- Create vision
		ability:CreateVisibilityNode(spirit:GetAbsOrigin(), self.vision_radius, self.vision_duration)

		-- Kill
		spirit:ForceKill( true )
	end
end

------------------------------
--		SPIRITS	TOGGLE		--
------------------------------
imba_wisp_spirits_toggle = class({})
function imba_wisp_spirits_toggle:OnSpellStart()
	if IsServer() then
		local caster 	= self:GetCaster()
		local ability 	= caster:FindAbilityByName("imba_wisp_spirits")
		local spirits_movementFactor = ability.spirits_movementFactor

		if spirits_movementFactor == 1 then
			ability.spirits_movementFactor = -1			
		else
			ability.spirits_movementFactor = 1
		end
	end
end

------------------------------
--		OVERCHARGE		--
------------------------------
imba_wisp_overcharge = class({})
LinkLuaModifier("modifier_imba_wisp_overcharge", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_overcharge_drain", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
function imba_wisp_overcharge:IsNetherWardStealable()
	return false
end

function imba_wisp_overcharge:AddOvercharge(caster, target)
		local ability 			= caster:FindAbilityByName("imba_wisp_overcharge")
		local tether_ability 	= caster:FindAbilityByName("imba_wisp_tether")

		local ability_level 		= ability:GetLevel() - 1
		local bonus_attack_speed	= ability:GetLevelSpecialValueFor("bonus_attack_speed", ability_level)
		local bonus_cast_speed		= ability:GetLevelSpecialValueFor("bonus_cast_speed", ability_level)
		local bonus_missile_speed 	= ability:GetLevelSpecialValueFor("bonus_missile_speed", ability_level)
		local bonus_damage_pct 		= ability:GetLevelSpecialValueFor("bonus_damage_pct", ability_level)
		local bonus_attack_range 	= ability:GetLevelSpecialValueFor("bonus_attack_range", ability_level)
		local bonus_regen 		 	= 0

		if caster:HasTalent("special_bonus_imba_wisp_3") then 
			local bonus_pct 		= caster:FindTalentValue("special_bonus_imba_wisp_3", "bonus_effect")
			bonus_attack_speed 		= bonus_attack_speed * bonus_pct
			bonus_cast_speed 		= bonus_cast_speed * bonus_pct
			bonus_missile_speed 	= bonus_missile_speed * bonus_pct
			bonus_damage_pct 		= bonus_damage_pct * bonus_pct
			bonus_attack_range 		= bonus_attack_range * bonus_pct
		end

		if caster:HasTalent("special_bonus_imba_wisp_7") then 
			bonus_regen 			= caster:FindTalentValue("special_bonus_imba_wisp_7", "bonus_regen")
		end

		-- set stats for client
		CustomNetTables:SetTableValue(
			"player_table", 
			tostring(caster:GetPlayerOwnerID()), 
			{ 	
				overcharge_bonus_attack_speed 	= bonus_attack_speed,
				overcharge_bonus_cast_speed 	= bonus_cast_speed,
				overcharge_bonus_missile_speed 	= bonus_missile_speed,
				overcharge_bonus_damage_pct 	= bonus_damage_pct,
				overcharge_bonus_attack_range 	= bonus_attack_range,
				overcharge_bonus_regen 			= bonus_regen
			})

		target:AddNewModifier(
				caster, 
				ability, 
				"modifier_imba_wisp_overcharge", 
				{
					duration 				= -1,
					bonus_attack_speed 		= bonus_attack_speed,
					bonus_cast_speed 		= bonus_cast_speed,
					bonus_missile_speed 	= bonus_missile_speed,
					bonus_damage_pct 		= bonus_damage_pct,
					bonus_attack_range 		= bonus_attack_range,
					bonus_regen 			= bonus_regen
				})
end

function imba_wisp_overcharge:OnToggle()
	if IsServer() then 
		local caster 			= self:GetCaster()
		local ability 			= caster:FindAbilityByName("imba_wisp_overcharge")
		local tether_ability 	= caster:FindAbilityByName("imba_wisp_tether")

		if ability:GetToggleState() then

			EmitSoundOn("Hero_Wisp.Overcharge", caster)

			local ability_level 		= ability:GetLevel() - 1
			local drain_interval 		= ability:GetLevelSpecialValueFor("drain_interval", ability_level)
			local drain_pct 			= ability:GetLevelSpecialValueFor("drain_pct", ability_level)
			drain_pct 					= drain_pct / 100

			imba_wisp_overcharge:AddOvercharge(caster, caster)

			if caster:HasModifier("modifier_imba_wisp_tether") then
				imba_wisp_overcharge:AddOvercharge(caster, tether_ability.target)
			end

			if caster:HasTalent("special_bonus_imba_wisp_7") then 
				local additional_drain = caster:FindTalentValue("special_bonus_imba_wisp_3", "bonus_drain")
				drain_pct = drain_pct + additional_drain
			end

			caster:AddNewModifier( caster, ability, "modifier_imba_wisp_overcharge_drain", { duration = -1, drain_interval = drain_interval, drain_pct = drain_pct })
			
		else
			caster:StopSound("Hero_Wisp.Overcharge")
			caster:RemoveModifierByName("modifier_imba_wisp_overcharge")
			caster:RemoveModifierByName("modifier_imba_wisp_overcharge_drain")

			if caster:HasModifier("modifier_imba_wisp_tether") then
				tether_ability.target:RemoveModifierByName("modifier_imba_wisp_overcharge")
			end
		end
	end
end

----------------------------------
--	Overchargge buff modifier	--
----------------------------------
modifier_imba_wisp_overcharge = class({})
function modifier_imba_wisp_overcharge:IsBuff() return true end
function modifier_imba_wisp_overcharge:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
		MODIFIER_PROPERTY_CASTTIME_PERCENTAGE,
		MODIFIER_PROPERTY_PROJECTILE_SPEED_BONUS,
		MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE,
		MODIFIER_PROPERTY_ATTACK_RANGE_BONUS,
		MODIFIER_PROPERTY_MANA_REGEN_CONSTANT,
		MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT
	}
	return funcs
end

function modifier_imba_wisp_overcharge:OnCreated(params)
	if IsServer() then
		self.overcharge_pfx 		= ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_overcharge.vpcf", PATTACH_ABSORIGIN_FOLLOW, self:GetParent())
		self.bonus_attack_speed 	= params.bonus_attack_speed
		self.bonus_cast_speed 		= params.bonus_cast_speed
		self.bonus_missile_speed 	= params.bonus_missile_speed
		self.bonus_damage_pct 		= params.bonus_damage_pct
		self.bonus_attack_range 	= params.bonus_attack_range
		self.bonus_regen 			= params.bonus_regen
	else
		local net_table 			= CustomNetTables:GetTableValue("player_table", tostring(self:GetCaster():GetPlayerOwnerID())) or {}
		self.bonus_attack_speed 	= net_table.overcharge_bonus_attack_speed or 0
		self.bonus_cast_speed 		= net_table.overcharge_bonus_cast_speed or 0
		self.bonus_missile_speed	= net_table.overcharge_bonus_missile_speed or 0
		self.bonus_damage_pct		= net_table.overcharge_bonus_damage_pct or 0
		self.bonus_attack_range 	= net_table.overcharge_bonus_attack_range or 0
		self.bonus_regen 			= net_table.overcharge_bonus_regen or 0
	end
end

function modifier_imba_wisp_overcharge:OnRemoved()
	if IsServer() then
		ParticleManager:DestroyParticle(self.overcharge_pfx, false)
		if not self:GetCaster():HasModifier("modifier_imba_wisp_overcharge") then
			self:GetCaster():RemoveModifierByName("modifier_imba_wisp_overcharge_drain")
		end
	end
end

function modifier_imba_wisp_overcharge:GetModifierAttackSpeedBonus_Constant()
	return self.bonus_attack_speed
end

function modifier_imba_wisp_overcharge:GetModifierPercentageCasttime()
	return self.bonus_cast_speed
end

function modifier_imba_wisp_overcharge:GetModifierProjectileSpeedBonus()
	return self.bonus_missile_speed
end

function modifier_imba_wisp_overcharge:GetModifierIncomingDamage_Percentage()
	return self.bonus_damage_pct
end

function modifier_imba_wisp_overcharge:GetModifierAttackRangeBonus()
	return self.bonus_attack_range
end

function modifier_imba_wisp_overcharge:GetModifierConstantManaRegen()
	return self.bonus_regen
end

function modifier_imba_wisp_overcharge:GetModifierConstantHealthRegen()
	return self.bonus_regen
end


----------------------------------------------
--	Overchargge health/mana-drain modifier	--
----------------------------------------------
modifier_imba_wisp_overcharge_drain = class({})
function modifier_imba_wisp_overcharge_drain:IsHidden() return true end
function modifier_imba_wisp_overcharge_drain:OnCreated(params)
	if IsServer() then
		self.caster 		= self:GetCaster()
		self.ability 		= self:GetAbility()
		self.drain_pct 		= params.drain_pct
		self.drain_interval = params.drain_interval
		self.deltaDrainPct	= self.drain_interval * self.drain_pct
		self:StartIntervalThink(self.drain_interval)
	end
end

function modifier_imba_wisp_overcharge_drain:OnIntervalThink()

	ApplyDamage( {
		victim = self.caster,
		attacker = self.caster,
		damage = self.caster:GetHealth() * self.deltaDrainPct,
		damage_type = DAMAGE_TYPE_PURE,
	} )

	self.caster:SpendMana( self.caster:GetMana() * self.deltaDrainPct, self.ability )
end

------------------------------
--			RELOCATE		--
------------------------------
imba_wisp_relocate = class({})
LinkLuaModifier("modifier_imba_wisp_relocate", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_relocate_cast_delay", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
function imba_wisp_relocate:GetBehavior()
	if IsServer() then
		return DOTA_ABILITY_BEHAVIOR_UNIT_TARGET + DOTA_ABILITY_BEHAVIOR_OPTIONAL_POINT
	else
		return DOTA_ABILITY_BEHAVIOR_POINT + DOTA_ABILITY_BEHAVIOR_OPTIONAL_UNIT_TARGET
	end
end

function imba_wisp_relocate:OnSpellStart()
	if IsServer() then
		local unit 					= self:GetCursorTarget()
		local caster 				= self:GetCaster()
		local ability 				= caster:FindAbilityByName("imba_wisp_relocate")
		local tether_ability 		= caster:FindAbilityByName("imba_wisp_tether")
		local ability_level 		= ability:GetLevel()
		local target_point 			= self:GetCursorPosition()
		local vision_radius 		= ability:GetLevelSpecialValueFor("vision_radius", ability_level)
		local cast_delay 			= ability:GetLevelSpecialValueFor("cast_delay", ability_level)
		local return_time 			= ability:GetLevelSpecialValueFor("return_time", ability_level)
		local destroy_tree_radius	= ability:GetSpecialValueFor("destroy_tree_radius")
	
		if unit == caster then
			if caster:GetTeam() == DOTA_TEAM_GOODGUYS then
				-- radiant fountain location
				target_point = Vector(-7168, -6646, 528)
			else
				-- dire fountain location
				target_point = Vector(7037, 6458, 512)
			end
		end

		-- remember where too return
		ability.relocate_target_point = target_point

		local pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_relocate_marker_endpoint.vpcf", PATTACH_CUSTOMORIGIN, caster)
		ParticleManager:SetParticleControl(pfx, 0, target_point)

		-- Store the particle ID
		ability.relocate_endpointPfx = pfx

		-- Create vision
		ability:CreateVisibilityNode(target_point, vision_radius, cast_delay)

		caster:AddNewModifier(caster, ability, "modifier_imba_wisp_relocate_cast_delay", {duration = cast_delay})

		Timers:CreateTimer({
			endTime = cast_delay,
			callback = function()
				ParticleManager:DestroyParticle(pfx, false)
				if not imba_wisp_relocate:InterruptRelocate(caster, ability) then
					GridNav:DestroyTreesAroundPoint(target_point, destroy_tree_radius, false)

					caster:SwapAbilities("imba_wisp_relocate", "imba_wisp_relocate_break", false, true)
					local break_ability = caster:FindAbilityByName("imba_wisp_relocate_break")
					break_ability:SetLevel(1)
				
					ability.origin = caster:GetAbsOrigin()

					if caster:HasModifier("modifier_imba_wisp_tether") and tether_ability.target:IsHero() then
						ability.ally_origin = tether_ability.target:GetAbsOrigin()
						ability.ally 		= tether_ability.target 
					else
						ability.ally_origin = nil
						ability.ally 		= nil
					end

					caster:AddNewModifier( caster, ability, "modifier_imba_wisp_relocate", { duration = return_time, return_time = return_time })
				end
			end
		})
	end
end

function imba_wisp_relocate:InterruptRelocate(caster, ability)
	if not caster:IsAlive() or caster:IsStunned() or caster:IsHexed() or caster:IsNightmared() or caster:IsOutOfGame() then
		return true
	end

	return false
end

----------------------
--	Relocate timer	--
----------------------
modifier_imba_wisp_relocate_cast_delay = class({})


--------------------------
--	Relocate modifier	--
--------------------------
modifier_imba_wisp_relocate = class({})
function modifier_imba_wisp_relocate:OnCreated(params)
	if IsServer() then
		local caster 		= self:GetCaster()
		local ability 		= self:GetAbility()
		local ally 			= ability.ally

		self.return_time	= params.return_time

		-- Create marker at origin
		self.caster_origin_pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_relocate_marker.vpcf", PATTACH_CUSTOMORIGIN, caster)
		ParticleManager:SetParticleControl(self.caster_origin_pfx, 0, caster:GetAbsOrigin())

		-- Add teleport effect
		self.caster_teleport_pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_relocate_teleport.vpcf", PATTACH_CUSTOMORIGIN, caster)
		ParticleManager:SetParticleControlEnt(self.caster_teleport_pfx, 0, caster, PATTACH_POINT, "attach_hitloc", caster:GetAbsOrigin(), true)

		-- Move units
		caster:SetAbsOrigin(ability.relocate_target_point)

		if caster:HasModifier("modifier_imba_wisp_tether") then
			self.ally_teleport_pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_relocate_teleport.vpcf", PATTACH_CUSTOMORIGIN, ally)
			ParticleManager:SetParticleControlEnt(self.ally_teleport_pfx, 0, ally, PATTACH_POINT, "attach_hitloc", ally:GetAbsOrigin(), true)
			ally:SetAbsOrigin(ability.relocate_target_point + Vector( 0, 100, 0 ))
		end

		self.relocate_timerPfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_relocate_timer.vpcf", PATTACH_OVERHEAD_FOLLOW, caster)
		local timerCP1_x = self.return_time >= 10 and 1 or 0			
		local timerCP1_y = self.return_time % 10
		ParticleManager:SetParticleControl(self.relocate_timerPfx, 1, Vector( timerCP1_x, timerCP1_y, 0 ) )

		self:StartIntervalThink(1.0)
	end
end

function modifier_imba_wisp_relocate:OnIntervalThink()
	self.return_time = self.return_time - 1
	local timerCP1_x = self.return_time >= 10 and 1 or 0
	local timerCP1_y = self.return_time % 10
	ParticleManager:SetParticleControl(self.relocate_timerPfx, 1, Vector( timerCP1_x, timerCP1_y, 0 ) )
end

function modifier_imba_wisp_relocate:OnRemoved()
	if IsServer() then
		local caster = self:GetCaster()
		local ability = self:GetAbility();

		-- Add teleport effect
		self.caster_teleport_pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_relocate_teleport.vpcf", PATTACH_CUSTOMORIGIN, caster)
		ParticleManager:SetParticleControlEnt(self.caster_teleport_pfx, 0, caster, PATTACH_POINT, "attach_hitloc", caster:GetAbsOrigin(), true)

		ParticleManager:DestroyParticle(self.relocate_timerPfx, false)
		ParticleManager:DestroyParticle(self.caster_origin_pfx, false)

		self:GetCaster():SetAbsOrigin(ability.origin)

		if caster:HasModifier("modifier_imba_wisp_tether") and caster:IsAlive() then
			local tether_ability 	= caster:FindAbilityByName("imba_wisp_tether")
			self.ally_teleport_pfx 	= ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_relocate_teleport.vpcf", PATTACH_CUSTOMORIGIN, tether_ability.target)
			ParticleManager:SetParticleControlEnt(self.ally_teleport_pfx, 0, tether_ability.target, PATTACH_POINT, "attach_hitloc", tether_ability.target:GetAbsOrigin(), true)

			if ability.ally_origin == nil then
				ability.ally_origin = ability.origin + Vector( 0, 100, 0 ) 
			end
			tether_ability.target:SetAbsOrigin(ability.ally_origin)
		end

		caster:SwapAbilities("imba_wisp_relocate_break", "imba_wisp_relocate", false, true)
	end
end

------------------------------
--		RELOCATE BREAK		--
------------------------------
imba_wisp_relocate_break = class({})
function imba_wisp_relocate_break:OnSpellStart() 
	if IsServer() then
		local caster = self:GetCaster()
		caster:RemoveModifierByName("modifier_imba_wisp_relocate")
	end
end

------------------------------
--	IO AOE ATTACK TALENT	--
------------------------------
modifier_special_bonus_imba_wisp_5 = class({
	IsHidden      = function(self) return true  end,
	RemoveOnDeath = function(self) return false end })

function modifier_special_bonus_imba_wisp_5:DeclareFunctions()
	local decFuncs = {
		MODIFIER_EVENT_ON_ATTACK_LANDED
	}

	return decFuncs
end

function modifier_special_bonus_imba_wisp_5:OnAttackLanded( params )
	if IsServer() then
		local parent = self:GetParent()
		local target = params.target
		if parent == params.attacker and target:GetTeamNumber() ~= parent:GetTeamNumber() then
			local splash_radius 	= parent:FindTalentValue("special_bonus_imba_wisp_5", "splash_radius")
			local splash_damage_pct = parent:FindTalentValue("special_bonus_imba_wisp_5", "splash_damage_pct")

			local nearby_enemy_units = FindUnitsInRadius(	
				parent:GetTeam(), 
				target:GetAbsOrigin(), 
				nil, 
				splash_radius, 
				DOTA_UNIT_TARGET_TEAM_ENEMY,
				DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, 
				DOTA_UNIT_TARGET_FLAG_NOT_ANCIENTS, 
				FIND_ANY_ORDER, 
				false)

				local damage_table 			= {}
				damage_table.attacker 		= parent
				--damage_table.ability 		= nil
				damage_table.damage_type 	= DAMAGE_TYPE_PHYSICAL 
				damage_table.damage 		= parent:GetAttackDamage() * (splash_damage_pct / 100)

			if nearby_enemy_units ~= nil then
			for _,enemy in pairs(nearby_enemy_units) do
				if enemy ~= parent and enemy ~= target then
						damage_table.victim = enemy
						ApplyDamage(damage_table)
					end
				end
			end
		end
	end
end

LinkLuaModifier("modifier_imba_wisp_swap_spirits_disarm", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_wisp_swap_spirits_silence", "hero/hero_wisp.lua", LUA_MODIFIER_MOTION_NONE)

imba_wisp_swap_spirits = class({})

function imba_wisp_swap_spirits:IsInnateAbility()
	return true
end

function imba_wisp_swap_spirits:GetIntrinsicModifierName()
	return "modifier_imba_wisp_swap_spirits_silence"
end

function imba_wisp_swap_spirits:GetAbilityTextureName()
	if self:GetCaster():HasModifier("modifier_imba_wisp_swap_spirits_silence") then
		return "custom/kunnka_tide_high"
	elseif self:GetCaster():HasModifier("modifier_imba_wisp_swap_spirits_disarm") then
		return "custom/kunnka_tide_red"
	end
end

function imba_wisp_swap_spirits:OnSpellStart()
	if self:GetCaster():HasModifier("modifier_imba_wisp_swap_spirits_disarm") then
		self:GetCaster():RemoveModifierByName("modifier_imba_wisp_swap_spirits_disarm")
		self:GetCaster():AddNewModifier(self:GetCaster(), self, "modifier_imba_wisp_swap_spirits_silence", {})
	elseif self:GetCaster():HasModifier("modifier_imba_wisp_swap_spirits_silence") then
		self:GetCaster():RemoveModifierByName("modifier_imba_wisp_swap_spirits_silence")
		self:GetCaster():AddNewModifier(self:GetCaster(), self, "modifier_imba_wisp_swap_spirits_disarm", {})
	end
end

modifier_imba_wisp_swap_spirits_disarm = class({})

function modifier_imba_wisp_swap_spirits_disarm:IsHidden() return true end
function modifier_imba_wisp_swap_spirits_disarm:IsPurgable() return false end
function modifier_imba_wisp_swap_spirits_disarm:RemoveOnDeath() return false end

modifier_imba_wisp_swap_spirits_silence = class({})

function modifier_imba_wisp_swap_spirits_silence:IsHidden() return true end
function modifier_imba_wisp_swap_spirits_silence:IsPurgable() return false end
function modifier_imba_wisp_swap_spirits_silence:RemoveOnDeath() return false end
