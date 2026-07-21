--[[
 .____                  ________ ___.    _____                           __                
 |    |    __ _______   \_____  \\_ |___/ ____\_ __  ______ ____ _____ _/  |_  ___________ 
 |    |   |  |  \__  \   /   |   \| __ \   __\  |  \/  ___// ___\\__  \\   __\/  _ \_  __ \
 |    |___|  |  // __ \_/    |    \ \_\ \  | |  |  /\___ \\  \___ / __ \|  | (  <_> )  | \/
 |_______ \____/(____  /\_______  /___  /__| |____//____  >\___  >____  /__|  \____/|__|   
         \/          \/         \/    \/                \/     \/     \/                   
          \_Welcome to LuaObfuscator.com   (Alpha 0.10.9) ~  Much Love, Ferib 

]]--

local StrToNumber = tonumber;
local Byte = string.byte;
local Char = string.char;
local Sub = string.sub;
local Subg = string.gsub;
local Rep = string.rep;
local Concat = table.concat;
local Insert = table.insert;
local LDExp = math.ldexp;
local GetFEnv = getfenv or function()
	return _ENV;
end;
local Setmetatable = setmetatable;
local PCall = pcall;
local Select = select;
local Unpack = unpack or table.unpack;
local ToNumber = tonumber;
local function VMCall(ByteString, vmenv, ...)
	local DIP = 1;
	local repeatNext;
	ByteString = Subg(Sub(ByteString, 5), "..", function(byte)
		if (Byte(byte, 2) == 81) then
			repeatNext = StrToNumber(Sub(byte, 1, 1));
			return "";
		else
			local a = Char(StrToNumber(byte, 16));
			if repeatNext then
				local b = Rep(a, repeatNext);
				repeatNext = nil;
				return b;
			else
				return a;
			end
		end
	end);
	local function gBit(Bit, Start, End)
		if End then
			local Res = (Bit / (2 ^ (Start - 1))) % (2 ^ (((End - 1) - (Start - 1)) + 1));
			return Res - (Res % 1);
		else
			local Plc = 2 ^ (Start - 1);
			return (((Bit % (Plc + Plc)) >= Plc) and 1) or 0;
		end
	end
	local function gBits8()
		local a = Byte(ByteString, DIP, DIP);
		DIP = DIP + 1;
		return a;
	end
	local function gBits16()
		local a, b = Byte(ByteString, DIP, DIP + 2);
		DIP = DIP + 2;
		return (b * 256) + a;
	end
	local function gBits32()
		local a, b, c, d = Byte(ByteString, DIP, DIP + 3);
		DIP = DIP + 4;
		return (d * 16777216) + (c * 65536) + (b * 256) + a;
	end
	local function gFloat()
		local Left = gBits32();
		local Right = gBits32();
		local IsNormal = 1;
		local Mantissa = (gBit(Right, 1, 20) * (2 ^ 32)) + Left;
		local Exponent = gBit(Right, 21, 31);
		local Sign = ((gBit(Right, 32) == 1) and -1) or 1;
		if (Exponent == 0) then
			if (Mantissa == 0) then
				return Sign * 0;
			else
				Exponent = 1;
				IsNormal = 0;
			end
		elseif (Exponent == 2047) then
			return ((Mantissa == 0) and (Sign * (1 / 0))) or (Sign * NaN);
		end
		return LDExp(Sign, Exponent - 1023) * (IsNormal + (Mantissa / (2 ^ 52)));
	end
	local function gString(Len)
		local Str;
		if not Len then
			Len = gBits32();
			if (Len == 0) then
				return "";
			end
		end
		Str = Sub(ByteString, DIP, (DIP + Len) - 1);
		DIP = DIP + Len;
		local FStr = {};
		for Idx = 1, #Str do
			FStr[Idx] = Char(Byte(Sub(Str, Idx, Idx)));
		end
		return Concat(FStr);
	end
	local gInt = gBits32;
	local function _R(...)
		return {...}, Select("#", ...);
	end
	local function Deserialize()
		local Instrs = {};
		local Functions = {};
		local Lines = {};
		local Chunk = {Instrs,Functions,nil,Lines};
		local ConstCount = gBits32();
		local Consts = {};
		for Idx = 1, ConstCount do
			local Type = gBits8();
			local Cons;
			if (Type == 1) then
				Cons = gBits8() ~= 0;
			elseif (Type == 2) then
				Cons = gFloat();
			elseif (Type == 3) then
				Cons = gString();
			end
			Consts[Idx] = Cons;
		end
		Chunk[3] = gBits8();
		for Idx = 1, gBits32() do
			local Descriptor = gBits8();
			if (gBit(Descriptor, 1, 1) == 0) then
				local Type = gBit(Descriptor, 2, 3);
				local Mask = gBit(Descriptor, 4, 6);
				local Inst = {gBits16(),gBits16(),nil,nil};
				if (Type == 0) then
					Inst[3] = gBits16();
					Inst[4] = gBits16();
				elseif (Type == 1) then
					Inst[3] = gBits32();
				elseif (Type == 2) then
					Inst[3] = gBits32() - (2 ^ 16);
				elseif (Type == 3) then
					Inst[3] = gBits32() - (2 ^ 16);
					Inst[4] = gBits16();
				end
				if (gBit(Mask, 1, 1) == 1) then
					Inst[2] = Consts[Inst[2]];
				end
				if (gBit(Mask, 2, 2) == 1) then
					Inst[3] = Consts[Inst[3]];
				end
				if (gBit(Mask, 3, 3) == 1) then
					Inst[4] = Consts[Inst[4]];
				end
				Instrs[Idx] = Inst;
			end
		end
		for Idx = 1, gBits32() do
			Functions[Idx - 1] = Deserialize();
		end
		return Chunk;
	end
	local function Wrap(Chunk, Upvalues, Env)
		local Instr = Chunk[1];
		local Proto = Chunk[2];
		local Params = Chunk[3];
		return function(...)
			local Instr = Instr;
			local Proto = Proto;
			local Params = Params;
			local _R = _R;
			local VIP = 1;
			local Top = -1;
			local Vararg = {};
			local Args = {...};
			local PCount = Select("#", ...) - 1;
			local Lupvals = {};
			local Stk = {};
			for Idx = 0, PCount do
				if (Idx >= Params) then
					Vararg[Idx - Params] = Args[Idx + 1];
				else
					Stk[Idx] = Args[Idx + 1];
				end
			end
			local Varargsz = (PCount - Params) + 1;
			local Inst;
			local Enum;
			while true do
				Inst = Instr[VIP];
				Enum = Inst[1];
				if (Enum <= 11) then
					if (Enum <= 5) then
						if (Enum <= 2) then
							if (Enum <= 0) then
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							elseif (Enum > 1) then
								VIP = Inst[3];
							else
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							end
						elseif (Enum <= 3) then
							Stk[Inst[2]] = Inst[3];
						elseif (Enum == 4) then
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
						else
							Stk[Inst[2]] = Env[Inst[3]];
						end
					elseif (Enum <= 8) then
						if (Enum <= 6) then
							Stk[Inst[2]][Inst[3]] = Inst[4];
						elseif (Enum > 7) then
							do
								return;
							end
						elseif not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 9) then
						local A;
						Stk[Inst[2]] = Upvalues[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Upvalues[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						if not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum > 10) then
						Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
					else
						Stk[Inst[2]] = {};
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = {};
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = {};
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
					end
				elseif (Enum <= 17) then
					if (Enum <= 14) then
						if (Enum <= 12) then
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 13) then
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
						else
							local A = Inst[2];
							do
								return Unpack(Stk, A, A + Inst[3]);
							end
						end
					elseif (Enum <= 15) then
						local A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
					elseif (Enum > 16) then
						Stk[Inst[2]] = Upvalues[Inst[3]];
					else
						Stk[Inst[2]] = Stk[Inst[3]];
					end
				elseif (Enum <= 20) then
					if (Enum <= 18) then
						Stk[Inst[2]] = {};
					elseif (Enum > 19) then
						local A = Inst[2];
						local B = Stk[Inst[3]];
						Stk[A + 1] = B;
						Stk[A] = B[Inst[4]];
					else
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
					end
				elseif (Enum <= 22) then
					if (Enum == 21) then
						do
							return Stk[Inst[2]];
						end
					else
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
					end
				elseif (Enum == 23) then
					Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
				else
					local NewProto = Proto[Inst[3]];
					local NewUvals;
					local Indexes = {};
					NewUvals = Setmetatable({}, {__index=function(_, Key)
						local Val = Indexes[Key];
						return Val[1][Val[2]];
					end,__newindex=function(_, Key, Value)
						local Val = Indexes[Key];
						Val[1][Val[2]] = Value;
					end});
					for Idx = 1, Inst[4] do
						VIP = VIP + 1;
						local Mvm = Instr[VIP];
						if (Mvm[1] == 16) then
							Indexes[Idx - 1] = {Stk,Mvm[3]};
						else
							Indexes[Idx - 1] = {Upvalues,Mvm[3]};
						end
						Lupvals[#Lupvals + 1] = Indexes;
					end
					Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!2C012Q0003043Q005445585403023Q007275030A3Q007469746C655F68696E74032E3Q00456E6420E2809420D184D0B0D180D0BC20C2B72052696768744374726C20E2809420D181D0BAD180D18BD182D18C03093Q00686964655F68696E7403253Q0052696768744374726C20E2809420D0BED182D0BAD180D18BD182D18C20D0BCD0B5D0BDD18E03083Q007461625F686F6D65030E3Q00D093D0BBD0B0D0B2D0BDD0B0D18F030C3Q007461625F686F6D655F73756203463Q00D0A3D0BFD180D0B0D0B2D0BBD0B5D0BDD0B8D0B520D184D0B0D180D0BCD0BED0BC20D0B820D181D182D0B0D182D0B8D181D182D0B8D0BAD0B020D181D0B5D181D181D0B8D0B8030C3Q007461625F73652Q74696E677303123Q00D09DD0B0D181D182D180D0BED0B9D0BAD0B803103Q007461625F73652Q74696E67735F73756203413Q00D094D0BED0B1D18BD187D0B02C20D0B1D0B5D0B7D0BED0BFD0B0D181D0BDD0BED181D182D18C20D0B820D0B0D0B2D182D0BE2DD0BFD180D0BED0B4D0B0D0B6D0B0030B3Q007461625F646973636F726403073Q00446973636F7264030F3Q007461625F646973636F72645F73756203343Q00576562682Q6F6B2C20D182D0B0D0B9D0BCD0B8D0BDD0B3D0B820D0B820D182D0B5D181D18220D0BED182D187D191D182D0BED0B2030B3Q007461625F63726564697473030E3Q00D09AD180D0B5D0B4D0B8D182D18B030F3Q007461625F637265646974735F73756203253Q00D09E20D181D0BAD180D0B8D0BFD182D0B520D0B820D0BAD0BED0BDD182D0B0D0BAD182D18B030A3Q006B65795F756E7061696403203Q00D094D0BED181D182D183D0BF20D0BDD0B520D0BED0BFD0BBD0B0D187D0B5D0BD03143Q006B65795F61637469766174696F6E5F6C6162656C031B3Q00D09AD0BBD18ED18720D0B0D0BAD182D0B8D0B2D0B0D186D0B8D0B8030C3Q006B65795F676174655F73756203283Q00D092D0B2D0B5D0B4D0B820D0BAD0BBD18ED18720D0B4D0BED181D182D183D0BFD0B02050616E6461030E3Q006B65795F676174655F6669656C6403173Q00D09AD09BD0AED0A720D094D09ED0A1D0A2D0A3D09FD09003143Q006B65795F676174655F706C616365686F6C64657203203Q00D092D181D182D0B0D0B2D18C20D0BAD0BBD18ED18720D0B8D0B72050616E646103113Q006B65795F676174655F636F6E74696E756503143Q00D09FD180D0BED0B4D0BED0BBD0B6D0B8D182D18C030C3Q006B65795F676174655F62757903193Q00D09AD183D0BFD0B8D182D18C20D0BAD0BBD18ED18720E2869203113Q006B65795F676174655F636865636B696E67031E3Q00D09FD180D0BED0B2D0B5D180D0BAD0B020D0BAD0BBD18ED187D0B03Q2E03123Q006B65795F676174655F766572696679696E6703133Q00D09FD180D0BED0B2D0B5D180D0BAD0B03Q2E03153Q006B65795F676174655F6C696E6B5F6D692Q73696E6703243Q00D0A1D181D18BD0BBD0BAD0B020D0BDD0B520D0BDD0B0D181D182D180D0BED0B5D0BDD0B003143Q006B65795F676174655F6C696E6B5F636F70696564032A3Q00D0A1D181D18BD0BBD0BAD0B02046756E50617920D181D0BAD0BED0BFD0B8D180D0BED0B2D0B0D0BDD0B0030E3Q006B65795F676174655F656E74657203133Q00D092D0B2D0B5D0B4D0B820D0BAD0BBD18ED18703113Q006B65795F676174655F612Q63657074656403153Q00D09AD0BBD18ED18720D0BFD180D0B8D0BDD18FD18203103Q006B65795F676174655F696E76616C696403193Q00D09DD0B5D0B2D0B5D180D0BDD18BD0B920D0BAD0BBD18ED187030D3Q006B65795F676174655F662Q6F7403103Q0050616E6461204B65792053797374656D03103Q006B65795F7374617475735F756E74696C030F3Q00D09AD0BBD18ED1873A20D0B4D0BE2003113Q006B65795F7374617475735F61637469766503173Q00D09AD0BBD18ED18720D0B0D0BAD182D0B8D0B2D0B5D0BD030B3Q006B65795F7072656D69756D030B3Q0020C2B7205072656D69756D03113Q006B65795F652Q725F70616E64615F6C696203363Q00D09DD0B520D0B7D0B0D0B3D180D183D0B7D0B8D0BBD0B0D181D18C20D0B1D0B8D0B1D0BBD0B8D0BED182D0B5D0BAD0B02050616E646103113Q006B65795F652Q725F70616E64615F343034033F3Q00D0A1D0B5D180D0B2D0B8D1812050616E646120D0BDD0B520D0BDD0B0D0B9D0B4D0B5D0BD2028343034292E20D09FD180D0BED0B2D0B5D180D18C2049443A2003173Q006B65795F652Q725F696E76616C69645F6578706972656403313Q00D09DD0B5D0B2D0B5D180D0BDD18BD0B920D0B8D0BBD0B820D0B8D181D182D191D0BAD188D0B8D0B920D0BAD0BBD18ED18703143Q006B65795F652Q725F636865636B5F6661696C6564032F3Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD180D0BED0B2D0B5D180D0B8D182D18C20D0BAD0BBD18ED187030E3Q0070616E656C5F636F6E74726F6C7303143Q00D0A3D0BFD180D0B0D0B2D0BBD0B5D0BDD0B8D0B5030D3Q0070616E656C5F73652Q73696F6E030C3Q00D0A1D0B5D181D181D0B8D18F030F3Q0070616E656C5F74705F68656967687403113Q00D092D18BD181D0BED182D0B020D0A2D09F03103Q00746F2Q676C655F6175746F737461727403223Q00D0A1D182D0B0D180D18220D0BFD180D0B820D0B7D0B0D0B3D180D183D0B7D0BAD0B5030F3Q00746F2Q676C655F6175746F6661726D03113Q00D090D0B2D182D0BE20D184D0B0D180D0BC030D3Q00746F2Q676C655F72656A6F696E03293Q00D090D0B2D182D0BE20D0BFD180D0B820D181D0BCD0B5D0BDD0B520D181D0B5D180D0B2D0B5D180D0B0030B3Q00737461745F737461747573030C3Q00D0A1D182D0B0D182D183D181030A3Q00737461745F74722Q6573031D3Q00D0A1D180D183D0B1D0B8D0BB20D0B4D0B5D180D0B5D0B2D18CD0B5D0B2030B3Q00737461745F73746F6E657303193Q00D0A1D180D183D0B1D0B8D0BB20D0BAD0B0D0BCD0BDD0B5D0B903093Q00737461745F6C2Q6F7403163Q00D09BD183D18220D0BDD0B020D0B7D0B5D0BCD0BBD0B503093Q00737461745F74696D6503153Q00D092D180D0B5D0BCD18F20D184D0B0D180D0BCD0B003093Q00737461745F6D6F6465030A3Q00D0A0D0B5D0B6D0B8D0BC030C3Q00736C696465725F74722Q6573030E3Q00D094D0B5D180D0B5D0B2D18CD18F030D3Q00736C696465725F73746F6E6573030A3Q00D09AD0B0D0BCD0BDD0B8030A3Q007365635F6D696E696E67030C3Q00D0B4D0BED0B1D18BD187D0B0030C3Q00746F2Q676C655F6F7262697403263Q00D09AD180D183D0B6D0B5D0BDD0B8D0B520D0B2D0BED0BAD180D183D0B320D186D0B5D0BBD0B8030A3Q00746F2Q676C655F61696D03163Q00D090D182D0B0D0BAD0B020D0B220D186D0B5D0BBD18C030B3Q00746F2Q676C655F666B657903103Q00D09AD0BBD0B0D0B2D0B8D188D0B02046030C3Q00746F2Q676C655F636C69636B030F3Q00D09AD0BBD0B8D0BA20D09BD09AD09C03123Q00736C696465725F6F726269745F73702Q6564031B3Q00D0A1D0BAD0BED180D0BED181D182D18C20D0BAD180D183D0B3D0B003113Q00736C696465725F6F726269745F73697A6503193Q00D094D0B8D0B0D0BCD0B5D182D18020D0BAD180D183D0B3D0B0030A3Q007365635F73616665747903183Q00D0B1D0B5D0B7D0BED0BFD0B0D181D0BDD0BED181D182D18C030F3Q00746F2Q676C655F626C6F636B5F7569031D3Q00D091D0BBD0BED0BA20554920D0BFD180D0B820D184D0B0D180D0BCD0B503133Q00746F2Q676C655F626C6F636B5F74726164657303173Q00D091D0BBD0BED0BA20D182D180D0B5D0B9D0B4D0BED0B2030D3Q0068696E745F626C6F636B5F7569033A3Q00D0A1D0BAD180D18BD0B2D0B0D0B5D18220D0B8D0B3D180D0BED0B2D18BD0B520D0BCD0B5D0BDD18E20D0BFD180D0B820D184D0B0D180D0BCD0B5030A3Q007365635F616E74697470030D3Q00D0B0D0BDD182D0B82DD182D0BF030D3Q00746F2Q676C655F616E7469747003163Q00D090D0BDD182D0B82DD0A2D09F20D0B7D0BED0BDD0B003103Q00736C696465725F637562655F73697A6503153Q00D0A0D0B0D0B7D0BCD0B5D18020D0BAD183D0B1D0B0030E3Q0062746E5F706C6163655F6375626503243Q00D09FD0BED181D182D0B0D0B2D0B8D182D18C20D0BAD183D0B120D0B7D0B4D0B5D181D18C030F3Q0062746E5F637562655F706C61636564031B3Q00D09AD183D0B120D183D181D182D0B0D0BDD0BED0B2D0BBD0B5D0BD03103Q0062746E5F6E6F5F63686172616374657203193Q00D09DD0B5D18220D0BFD0B5D180D181D0BED0BDD0B0D0B6D0B0030B3Q0068696E745F616E74697470035B3Q00D09AD180D0B0D181D0BDD18BD0B920D0BAD183D0B120E2809420D0B7D0B0D0BFD180D0B5D18220D0BDD0B020D0A2D09F20D0B820D184D0B0D180D0BC2028D0B4D0B5D180D0B5D0B2D18CD18F20D0B820D0BAD0B0D0BCD0BDD0B82903073Q007365635F687562030A3Q00D186D0B5D0BDD182D180030F3Q00746F2Q676C655F6875625F77616974031A3Q00D09FD0B0D183D0B7D0B020D18320D181D0BFD0B0D0B2D0BDD0B0030D3Q0068696E745F6875625F7761697403443Q00D092D18BD0BAD0BB20E2809420D0A2D09F20D0B220D186D0B5D0BDD182D18020D0B1D0B5D0B720D0BED0B6D0B8D0B4D0B0D0BDD0B8D18F2033E280933820D181D0B5D0BA03083Q007365635F73652Q6C030E3Q00D0BFD180D0BED0B4D0B0D0B6D0B0030F3Q00746F2Q676C655F6175746F73652Q6C03173Q00D090D0B2D182D0BE20D0BFD180D0BED0B4D0B0D0B6D0B0030C3Q0062746E5F73652Q6C5F6E6F77031B3Q00D09FD180D0BED0B4D0B0D182D18C20D181D0B5D0B9D187D0B0D181030B3Q0062746E5F73652Q6C696E6703113Q00D09FD180D0BED0B4D0B0D0B6D0B03Q2E03093Q0068696E745F73652Q6C037F3Q00D090D0B2D182D0BE3A20D0BBD18ED0B1D0BED0B920D0BFD180D0B5D0B4D0BCD0B5D182203E20383Q392E20D09FD180D0B820D0A2D09F20D0B220D0B4D180D183D0B3D0BED0B920D0BFD0BBD0B5D0B9D18120D0BFD180D0BED0B3D180D0B5D181D18120D0B2206D6178692D6875622D73652Q6C2D73746174652E6A736F6E03113Q00736C696465725F73652Q6C5F636865636B03193Q00D09FD180D0BED0B2D0B5D180D0BAD0B02028D181D0B5D0BA2903093Q0073652Q6C5F62757379031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003073Q0073652Q6C5F7470031B3Q00D0A2D09F20D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D1833Q2E03093Q0073652Q6C5F646F6E65030C3Q00D093D0BED182D0BED0B2D0BE030A3Q0073652Q6C5F652Q726F72030C3Q00D09ED188D0B8D0B1D0BAD0B0030D3Q00776562682Q6F6B5F7469746C65030B3Q00576562682Q6F6B2055524C03103Q00776562682Q6F6B5F73617665645F6F6B032E3Q00D0A1D0BED185D180D0B0D0BDD18FD0B5D182D181D18F20D0B2206D6178692D6875622D636F6E6669672E6A736F6E03113Q00776562682Q6F6B5F73617665645F62616403473Q00D0A4D0B0D0B9D0BBD18B20D0BDD0B5D0B4D0BED181D182D183D0BFD0BDD18B20E2809420776562682Q6F6B20D0B4D0BE20D0BFD0B5D180D0B5D0B7D0B0D0BFD183D181D0BAD0B003103Q0062746E5F746573745F776562682Q6F6B03103Q00D0A2D0B5D181D18220776562682Q6F6B03083Q0062746E5F7361766503123Q00D0A1D0BED185D180D0B0D0BDD0B8D182D18C030C3Q00646973636F72645F68696E7403533Q00D0A1D18ED0B4D0B020D0B8D0B4D183D18220D0BBD0BED0B3D0B820D184D0B0D180D0BCD0B03A20D181D180D183D0B1D0B8D0BB2C20D0BBD183D1822C20D0B2D180D0B5D0BCD18F2C205265736F75726365732E030D3Q00646973636F72645F736176656403123Q00D0A1D0BED185D180D0B0D0BDD0B5D0BDD0BE03163Q00746F2Q676C655F646973636F72645F7265706F72747303173Q00D09ED182D187D191D182D18B20D0B220446973636F726403133Q00746F2Q676C655F646973636F72645F73746F7003203Q00D09BD0BED0B320D0BFD180D0B820D0BED181D182D0B0D0BDD0BED0B2D0BAD0B503133Q00746F2Q676C655F646973636F72645F73652Q6C03203Q00D09BD0BED0B320D0BFD0BED181D0BBD0B520D0BFD180D0BED0B4D0B0D0B6D0B803173Q00736C696465725F646973636F72645F696E74657276616C03193Q00D098D0BDD182D0B5D180D0B2D0B0D0BB2028D0BCD0B8D0BD29030B3Q007363726970745F6C696E65031E3Q00D090D0B2D182D0BE2DD184D0B0D180D0BC20D181D0BAD180D0B8D0BFD18203093Q0074675F62752Q746F6E03133Q0054656C656772616D20D0BAD0B0D0BDD0B0D0BB03093Q0074675F636F7069656403173Q00D0A1D0BAD0BED0BFD0B8D180D0BED0B2D0B0D0BDD0BE21030E3Q00637265646974735F7468616E6B73032D3Q00D0A1D0BFD0B0D181D0B8D0B1D0BE20D187D182D0BE20D0BFD0BED0BBD18CD0B7D183D0B5D188D18CD181D18F21030A3Q0070686173655F69646C6503103Q00D0BED0B6D0B8D0B4D0B0D0BDD0B8D0B5030C3Q0070686173655F736561726368030A3Q00D0BFD0BED0B8D181D0BA030A3Q0070686173655F6D696E65030A3Q0070686173655F7761697403133Q00D0B6D0B4D191D0BC20D0B4D180D0BED0BFD18B030D3Q0070686173655F636F2Q6C65637403083Q00D181D0B1D0BED180030A3Q0070686173655F73652Q6C03093Q0070686173655F687562030A3Q006D6F64655F74722Q6573030E3Q00D0B4D0B5D180D0B5D0B2D18CD18F030B3Q006D6F64655F73746F6E6573030A3Q00D0BAD0B0D0BCD0BDD0B8030B3Q006D6F64655F73656172636803023Q00656E03223Q00456E6420E28094206661726D20C2B72052696768744374726C20E28094206869646503173Q0052696768744374726C20E28094206F70656E206D656E7503043Q00486F6D65031F3Q004661726D20636F6E74726F6C7320616E642073652Q73696F6E20737461747303083Q0053652Q74696E6773031C3Q004D696E696E672C2073616665747920616E64206175746F2D73652Q6C03213Q00576562682Q6F6B2C2074696D696E677320616E642074657374207265706F72747303073Q0043726564697473031D3Q0041626F7574207468652073637269707420616E6420636F6E7461637473030F3Q00412Q63652Q73206E6F742070616964030E3Q0041637469766174696F6E206B6579031B3Q00456E74657220796F75722050616E646120612Q63652Q73206B6579030A3Q00412Q43452Q53204B455903143Q005061737465206B65792066726F6D2050616E646103083Q00436F6E74696E7565030B3Q00427579206B657920E28692030F3Q00436865636B696E67206B65793Q2E030C3Q00566572696679696E673Q2E03133Q004C696E6B206E6F7420636F6E6669677572656403123Q0046756E506179206C696E6B20636F70696564030B3Q00456E7465722061206B6579030C3Q004B657920612Q636570746564030B3Q00496E76616C6964206B6579030A3Q004B657920756E74696C20030A3Q004B657920616374697665031C3Q004661696C656420746F206C6F61642050616E6461206C69627261727903293Q0050616E64612073657276696365206E6F7420666F756E642028343034292E20436865636B2049443A2003163Q00496E76616C6964206F722065787069726564206B657903143Q00436F756C64206E6F7420766572696679206B657903083Q00436F6E74726F6C7303073Q0053652Q73696F6E03093Q00545020686569676874030D3Q005374617274206F6E206C6F616403093Q004175746F206661726D03123Q004175746F206F6E2073657276657220686F7003063Q0053746174757303093Q0054722Q657320637574030C3Q0053746F6E6573206D696E6564030B3Q0047726F756E64206C2Q6F7403093Q004661726D2074696D6503043Q004D6F646503053Q0054722Q657303063Q0053746F6E657303063Q006D696E696E67030C3Q004F7262697420746172676574030D3Q0041696D2061742074617267657403053Q0046206B6579030A3Q004C65667420636C69636B030B3Q004F726269742073702Q6564030A3Q004F726269742073697A6503063Q0073616665747903163Q00426C6F636B205549207768696C65206661726D696E67030C3Q00426C6F636B2074726164657303213Q00486964657320696E2D67616D65206D656E7573207768696C65206661726D696E6703073Q00616E74692D7470030C3Q00416E74692D5450207A6F6E6503093Q00437562652073697A65030F3Q00506C61636520637562652068657265030B3Q004375626520706C61636564030C3Q004E6F20636861726163746572032E3Q00526564206375626520626C6F636B7320545020616E64206661726D202874722Q657320616E642073746F6E6573292Q033Q00687562030E3Q00506175736520617420737061776E03283Q004F2Q6620E2809420545020746F2063656E74657220776974686F75742033E280933873207761697403073Q0073652Q6C696E6703093Q004175746F2073652Q6C03083Q0053652Q6C206E6F77030A3Q0053652Q6C696E673Q2E03473Q004175746F3A20616E79206974656D203E20383Q392E2043726F2Q732D706C6163652070726F6772652Q7320696E206D6178692D6875622D73652Q6C2D73746174652E6A736F6E030B3Q00436865636B20287365632903143Q0053652Q6C20616C72656164792072752Q6E696E67030D3Q00545020746F2073652Q6C3Q2E03043Q00446F6E6503053Q00452Q726F72031D3Q00536176656420746F206D6178692D6875622D636F6E6669672E6A736F6E032B3Q0046696C657320756E617661696C61626C6520E2809420776562682Q6F6B20756E74696C2072657374617274030C3Q005465737420776562682Q6F6B03043Q005361766503303Q004661726D206C6F677320676F20686572653A2063686F70732C206C2Q6F742C2074696D652C205265736F75726365732E03053Q005361766564030F3Q00446973636F7264207265706F727473030B3Q004C6F67206F6E2073746F70030E3Q004C6F672061667465722073652Q6C030E3Q00496E74657276616C20286D696E2903103Q004175746F2D6661726D2073637269707403103Q0054656C656772616D206368612Q6E656C03073Q00436F706965642103113Q005468616E6B7320666F72207573696E672103043Q0069646C6503063Q00736561726368030D3Q0077616974696E672064726F707303073Q00636F2Q6C65637403043Q0073652Q6C03053Q0074722Q657303063Q0073746F6E657303093Q006E6F726D616C697A6503013Q00740008013Q000A9Q0000013Q00024Q00023Q002500302Q00020003000400302Q00020005000600302Q00020007000800302Q00020009000A00302Q0002000B000C00302Q0002000D000E00302Q0002000F001000302Q00020011001200302Q00020013001400302Q00020015001600302Q00020017001800302Q00020019001A00302Q0002001B001C00302Q0002001D001E00302Q0002001F002000302Q00020021002200302Q00020023002400302Q00020025002600302Q00020027002800302Q00020029002A00302Q0002002B002C00302Q0002002D002E00302Q0002002F003000302Q00020031003200302Q00020033003400302Q00020035003600302Q00020037003800302Q00020039003A00302Q0002003B003C00302Q0002003D003E00302Q0002003F004000302Q00020041004200302Q00020043004400302Q00020045004600302Q00020047004800302Q00020049004A00302Q0002004B004C00302Q0002004D004E00302Q0002004F005000302Q00020051005200302Q00020053005400302Q00020055005600302Q00020057005800302Q00020059005A00302Q0002005B005C00302Q0002005D005E00302Q0002005F006000302Q00020061006200302Q00020063006400302Q00020065006600302Q00020067006800302Q00020069006A00302Q0002006B006C00302Q0002006D006E00302Q0002006F007000302Q00020071007200302Q00020073007400302Q00020075007600302Q00020077007800302Q00020079007A00302Q0002007B007C00302Q0002007D007E00302Q0002007F008000302Q00020081008200302Q00020083008400302Q00020085008600302Q00020087008800302Q00020089008A00302Q0002008B008C00302Q0002008D008E00302Q0002008F009000302Q00020091009200302Q00020093009400302Q00020095009600302Q00020097009800302Q00020099009A00302Q0002009B009C0030060002009D009E00300E0002009F00A000302Q000200A100A200302Q000200A300A400302Q000200A500A600302Q000200A700A800302Q000200A900AA00302Q000200AB00AC00302Q000200AD00AE00302Q000200AF00B000302Q000200B100B200302Q000200B300B400302Q000200B500B600302Q000200B700B800302Q000200B900BA00302Q000200BB00BC00302Q000200BD00BE00302Q000200BF006000302Q000200C000C100302Q000200C200C300302Q000200C4008A00302Q000200C5008400302Q000200C600C700302Q000200C800C900302Q000200CA00BE00102Q0001000200024Q00023Q002500302Q0002000300CC00302Q0002000500CD00302Q0002000700CE00302Q0002000900CF00302Q0002000B00D000302Q0002000D00D100302Q0002000F001000302Q0002001100D200302Q0002001300D300302Q0002001500D400302Q0002001700D500302Q0002001900D600302Q0002001B00D700302Q0002001D00D800302Q0002001F00D900302Q0002002100DA00302Q0002002300DB00302Q0002002500DC00302Q0002002700DD00302Q0002002900DE00302Q0002002B00DF00302Q0002002D00E000302Q0002002F00E100302Q0002003100E200302Q00020033003400302Q0002003500E300302Q0002003700E400302Q00020039003A00302Q0002003B00E500302Q0002003D00E600302Q0002003F00E700302Q0002004100E800302Q0002004300E900302Q0002004500EA00302Q0002004700EB00302Q0002004900EC00302Q0002004B00ED00302Q0002004D00EE00302Q0002004F00EF00302Q0002005100F000302Q0002005300F100302Q0002005500F200302Q0002005700F300302Q0002005900F400302Q0002005B00F500302Q0002005D00F600302Q0002005F00F700302Q0002006100F800302Q0002006300F900302Q0002006500FA00302Q0002006700FB00302Q0002006900FC00302Q0002006B00FD00302Q0002006D00FE0030060002006F00FF003013000200712Q0001122Q0003002Q012Q00102Q00020073000300122Q00030002012Q00102Q00020075000300122Q00030003012Q00102Q00020077000300122Q00030004012Q00102Q00020079000300122Q00030005012Q00102Q0002007B000300122Q00030006012Q00102Q0002007D000300122Q00030007012Q00102Q0002007F000300122Q00030008012Q00102Q00020081000300122Q00030009012Q00102Q00020083000300122Q0003000A012Q00102Q00020085000300122Q0003000B012Q00102Q00020087000300122Q0003000C012Q00102Q00020089000300122Q0003000D012Q00102Q0002008B000300122Q0003000E012Q00102Q0002008D000300122Q0003000F012Q00102Q0002008F000300122Q00030010012Q00102Q00020091000300122Q00030011012Q00102Q00020093000300122Q00030012012Q00102Q00020095000300122Q00030013012Q00102Q00020097000300122Q00030014012Q00102Q00020099000300122Q00030015012Q00102Q0002009B000300302Q0002009D009E00122Q00030016012Q00102Q0002009F000300122Q00030017012Q00102Q000200A1000300122Q00030018012Q00102Q000200A3000300122Q00030019012Q00102Q000200A5000300122Q0003001A012Q00102Q000200A7000300122Q0003001B012Q00102Q000200A9000300122Q0003001C012Q00102Q000200AB000300122Q0003001D012Q00102Q000200AD000300122Q0003001E012Q00102Q000200AF000300122Q0003001F012Q00102Q000200B1000300122Q00030020012Q00102Q000200B3000300122Q00030021012Q00102Q000200B5000300122Q00030022012Q00102Q000200B7000300122Q00030023012Q00102Q000200B9000300122Q00030024012Q00102Q000200BB000300122Q00030025012Q00102Q000200BD000300302Q000200BF00F700122Q00030026012Q00102Q000200C0000300122Q00030027012Q001016000200C2000300122Q00030028012Q00102Q000200C4000300122Q00030009012Q00102Q000200C5000300122Q00030029012Q00102Q000200C6000300122Q0003002A012Q00102Q000200C8000300122Q00030025012Q00102Q000200CA000300102Q000100CB000200104Q000100010012030001002B012Q00021700026Q000B3Q000100020012030001002C012Q00061800020001000100012Q00108Q000B3Q000100022Q00153Q00024Q00083Q00013Q00023Q00053Q0003043Q007479706503063Q00737472696E6703053Q006C6F77657203023Q00656E03023Q007275010E3Q001205000100014Q001000026Q000F00010002000200260C0001000B000100020004023Q000B000100201400013Q00032Q000F00010002000200260C0001000B000100040004023Q000B0001001203000100044Q0015000100023Q001203000100054Q0015000100024Q00083Q00017Q00033Q0003093Q006E6F726D616C697A6503043Q005445585403023Q00727502194Q000900025Q00202Q0002000200014Q00038Q0002000200026Q00026Q00025Q00202Q0002000200024Q000200023Q00062Q0002000D000100010004023Q000D00012Q001100025Q0020010002000200020020010002000200032Q000400030002000100060700030017000100010004023Q001700012Q001100035Q0020010003000300020020010003000300032Q000400030003000100060700030017000100010004023Q001700012Q0010000300014Q0015000300024Q00083Q00017Q00", GetFEnv(), ...);
