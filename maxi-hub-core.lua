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
				if (Enum <= 214) then
					if (Enum <= 106) then
						if (Enum <= 52) then
							if (Enum <= 25) then
								if (Enum <= 12) then
									if (Enum <= 5) then
										if (Enum <= 2) then
											if (Enum <= 0) then
												local Results;
												local Edx;
												local Results, Limit;
												local B;
												local A;
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												B = Stk[Inst[3]];
												Stk[A + 1] = B;
												Stk[A] = B[Inst[4]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Results, Limit = _R(Stk[A](Stk[A + 1]));
												Top = (Limit + A) - 1;
												Edx = 0;
												for Idx = A, Top do
													Edx = Edx + 1;
													Stk[Idx] = Results[Edx];
												end
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Results = {Stk[A](Unpack(Stk, A + 1, Top))};
												Edx = 0;
												for Idx = A, Inst[4] do
													Edx = Edx + 1;
													Stk[Idx] = Results[Edx];
												end
												VIP = VIP + 1;
												Inst = Instr[VIP];
												VIP = Inst[3];
											elseif (Enum == 1) then
												local A;
												Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Inst[3];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Inst[3];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Inst[3];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Inst[3];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Inst[3];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Inst[3];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Stk[A] = Stk[A](Stk[A + 1]);
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
											else
												local A;
												Stk[Inst[2]] = Stk[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Stk[A](Stk[A + 1]);
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Stk[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Stk[A](Stk[A + 1]);
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Env[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Inst[3];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												Stk[Inst[2]] = Stk[Inst[3]];
												VIP = VIP + 1;
												Inst = Instr[VIP];
												A = Inst[2];
												Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
												VIP = VIP + 1;
												Inst = Instr[VIP];
												if not Stk[Inst[2]] then
													VIP = VIP + 1;
												else
													VIP = Inst[3];
												end
											end
										elseif (Enum <= 3) then
											local B;
											local A;
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Stk[A + 1]);
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											B = Stk[Inst[3]];
											Stk[A + 1] = B;
											Stk[A] = B[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3] ~= 0;
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
											VIP = VIP + 1;
											Inst = Instr[VIP];
											if not Stk[Inst[2]] then
												VIP = VIP + 1;
											else
												VIP = Inst[3];
											end
										elseif (Enum == 4) then
											Stk[Inst[2]] = {};
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Env[Inst[3]] = Stk[Inst[2]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											for Idx = Inst[2], Inst[3] do
												Stk[Idx] = nil;
											end
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Env[Inst[3]] = Stk[Inst[2]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]]();
										else
											local A;
											Env[Inst[3]] = Stk[Inst[2]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Unpack(Stk, A + 1, Inst[3]));
										end
									elseif (Enum <= 8) then
										if (Enum <= 6) then
											local A;
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Unpack(Stk, A + 1, Inst[3]));
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Stk[A + 1]);
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
										elseif (Enum > 7) then
											local A;
											Stk[Inst[2]] = {};
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Stk[A + 1]);
											VIP = VIP + 1;
											Inst = Instr[VIP];
											if (Stk[Inst[2]] ~= Inst[4]) then
												VIP = VIP + 1;
											else
												VIP = Inst[3];
											end
										else
											local A;
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Upvalues[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											do
												return Stk[A](Unpack(Stk, A + 1, Inst[3]));
											end
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											do
												return Unpack(Stk, A, Top);
											end
											VIP = VIP + 1;
											Inst = Instr[VIP];
											do
												return;
											end
										end
									elseif (Enum <= 10) then
										if (Enum > 9) then
											Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
										else
											local A;
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											if (Stk[Inst[2]] <= Stk[Inst[4]]) then
												VIP = VIP + 1;
											else
												VIP = Inst[3];
											end
										end
									elseif (Enum > 11) then
										Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
									else
										local B;
										local T;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = #Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										T = Stk[A];
										B = Inst[3];
										for Idx = 1, B do
											T[Idx] = Stk[A + Idx];
										end
									end
								elseif (Enum <= 18) then
									if (Enum <= 15) then
										if (Enum <= 13) then
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
										elseif (Enum > 14) then
											local A;
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Stk[A + 1]);
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Stk[A + 1]);
										else
											local A;
											Stk[Inst[2]] = Upvalues[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
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
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										end
									elseif (Enum <= 16) then
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									elseif (Enum == 17) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if (Stk[Inst[2]] == Inst[4]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									else
										local A;
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										for Idx = Inst[2], Inst[3] do
											Stk[Idx] = nil;
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									end
								elseif (Enum <= 21) then
									if (Enum <= 19) then
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										do
											return Stk[A](Unpack(Stk, A + 1, Inst[3]));
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										do
											return Unpack(Stk, A, Top);
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									elseif (Enum == 20) then
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
									else
										local A = Inst[2];
										local T = Stk[A];
										for Idx = A + 1, Inst[3] do
											Insert(T, Stk[Idx]);
										end
									end
								elseif (Enum <= 23) then
									if (Enum == 22) then
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
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
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									elseif (Inst[2] < Stk[Inst[4]]) then
										VIP = Inst[3];
									else
										VIP = VIP + 1;
									end
								elseif (Enum == 24) then
									local A = Inst[2];
									local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
									local Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								else
									Stk[Inst[2]] = #Stk[Inst[3]];
								end
							elseif (Enum <= 38) then
								if (Enum <= 31) then
									if (Enum <= 28) then
										if (Enum <= 26) then
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Inst[4];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
										elseif (Enum == 27) then
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											if Stk[Inst[2]] then
												VIP = VIP + 1;
											else
												VIP = Inst[3];
											end
										else
											Stk[Inst[2]] = Stk[Inst[3]] % Inst[4];
										end
									elseif (Enum <= 29) then
										local A = Inst[2];
										do
											return Stk[A], Stk[A + 1];
										end
									elseif (Enum == 30) then
										local A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
									else
										local A;
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										for Idx = Inst[2], Inst[3] do
											Stk[Idx] = nil;
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									end
								elseif (Enum <= 34) then
									if (Enum <= 32) then
										local A;
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										for Idx = Inst[2], Inst[3] do
											Stk[Idx] = nil;
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									elseif (Enum == 33) then
										local A;
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
									else
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return Stk[Inst[2]];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									end
								elseif (Enum <= 36) then
									if (Enum == 35) then
										if (Stk[Inst[2]] < Stk[Inst[4]]) then
											VIP = Inst[3];
										else
											VIP = VIP + 1;
										end
									else
										Stk[Inst[2]] = Stk[Inst[3]] / Inst[4];
									end
								elseif (Enum == 37) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] ~= Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								end
							elseif (Enum <= 45) then
								if (Enum <= 41) then
									if (Enum <= 39) then
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
									elseif (Enum > 40) then
										local Edx;
										local Results;
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Results = {Stk[A](Stk[A + 1])};
										Edx = 0;
										for Idx = A, Inst[4] do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if not Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									else
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if (Stk[Inst[2]] == Inst[4]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum <= 43) then
									if (Enum > 42) then
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									else
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum > 44) then
									local Edx;
									local Results, Limit;
									local B;
									local A;
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
									Top = (Limit + A) - 1;
									Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								else
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return Stk[Inst[2]];
									end
								end
							elseif (Enum <= 48) then
								if (Enum <= 46) then
									local A;
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								elseif (Enum == 47) then
									local T;
									local K;
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
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
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									B = Inst[3];
									K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									T = Stk[A];
									B = Inst[3];
									for Idx = 1, B do
										T[Idx] = Stk[A + Idx];
									end
								else
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 50) then
								if (Enum > 49) then
									local B = Stk[Inst[4]];
									if B then
										VIP = VIP + 1;
									else
										Stk[Inst[2]] = B;
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum > 51) then
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local B;
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Stk[Inst[4]]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
							end
						elseif (Enum <= 79) then
							if (Enum <= 65) then
								if (Enum <= 58) then
									if (Enum <= 55) then
										if (Enum <= 53) then
											local A;
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = {};
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Unpack(Stk, A + 1, Inst[3]));
										elseif (Enum == 54) then
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Inst[4];
										else
											local A;
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Stk[A + 1]);
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
										end
									elseif (Enum <= 56) then
										local K;
										local Edx;
										local Results, Limit;
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Results, Limit = _R(Stk[A]());
										Top = (Limit + A) - 1;
										Edx = 0;
										for Idx = A, Top do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										B = Inst[3];
										K = Stk[B];
										for Idx = B + 1, Inst[4] do
											K = K .. Stk[Idx];
										end
										Stk[Inst[2]] = K;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										do
											return Stk[A](Unpack(Stk, A + 1, Inst[3]));
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										do
											return Unpack(Stk, A, Top);
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									elseif (Enum == 57) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									else
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if not Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum <= 61) then
									if (Enum <= 59) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if not Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									elseif (Enum == 60) then
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									else
										local A;
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if not Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum <= 63) then
									if (Enum == 62) then
										if (Stk[Inst[2]] < Inst[4]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									else
										local A = Inst[2];
										local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
										Top = (Limit + A) - 1;
										local Edx = 0;
										for Idx = A, Top do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
									end
								elseif (Enum == 64) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] == Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
								end
							elseif (Enum <= 72) then
								if (Enum <= 68) then
									if (Enum <= 66) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
									elseif (Enum > 67) then
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										for Idx = Inst[2], Inst[3] do
											Stk[Idx] = nil;
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
									else
										local A;
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									end
								elseif (Enum <= 70) then
									if (Enum == 69) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										do
											return Stk[A](Unpack(Stk, A + 1, Inst[3]));
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										do
											return Unpack(Stk, A, Top);
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									else
										local K;
										local B;
										local A;
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										B = Inst[3];
										K = Stk[B];
										for Idx = B + 1, Inst[4] do
											K = K .. Stk[Idx];
										end
										Stk[Inst[2]] = K;
									end
								elseif (Enum > 71) then
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
								else
									local K;
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									B = Inst[3];
									K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return Stk[Inst[2]];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								end
							elseif (Enum <= 75) then
								if (Enum <= 73) then
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum > 74) then
									local A;
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = not Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								else
									local A;
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
								end
							elseif (Enum <= 77) then
								if (Enum == 76) then
									local A;
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									local B;
									local A;
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
								end
							elseif (Enum == 78) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							else
								Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
							end
						elseif (Enum <= 92) then
							if (Enum <= 85) then
								if (Enum <= 82) then
									if (Enum <= 80) then
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									elseif (Enum > 81) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									else
										local A;
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if (Stk[Inst[2]] == Inst[4]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum <= 83) then
									local K;
									local B;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									B = Inst[3];
									K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								elseif (Enum > 84) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								end
							elseif (Enum <= 88) then
								if (Enum <= 86) then
									local Results;
									local Edx;
									local Results, Limit;
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results, Limit = _R(Stk[A](Stk[A + 1]));
									Top = (Limit + A) - 1;
									Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results = {Stk[A](Unpack(Stk, A + 1, Top))};
									Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									VIP = Inst[3];
								elseif (Enum > 87) then
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							elseif (Enum <= 90) then
								if (Enum > 89) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								else
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum == 91) then
								local Edx;
								local Results;
								local A;
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results = {Stk[A](Stk[A + 1])};
								Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								VIP = Inst[3];
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 99) then
							if (Enum <= 95) then
								if (Enum <= 93) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								elseif (Enum > 94) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								else
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								end
							elseif (Enum <= 97) then
								if (Enum == 96) then
									VIP = Inst[3];
								else
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								end
							elseif (Enum > 98) then
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							else
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 102) then
							if (Enum <= 100) then
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 101) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							else
								Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
							end
						elseif (Enum <= 104) then
							if (Enum == 103) then
								if (Inst[2] <= Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							end
						elseif (Enum > 105) then
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
						end
					elseif (Enum <= 160) then
						if (Enum <= 133) then
							if (Enum <= 119) then
								if (Enum <= 112) then
									if (Enum <= 109) then
										if (Enum <= 107) then
											local K;
											local B;
											local A;
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Stk[A + 1]);
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											B = Inst[3];
											K = Stk[B];
											for Idx = B + 1, Inst[4] do
												K = K .. Stk[Idx];
											end
											Stk[Inst[2]] = K;
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Inst[4];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Inst[4];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Inst[4];
										elseif (Enum > 108) then
											local A;
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Unpack(Stk, A + 1, Inst[3]));
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										else
											local A;
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]];
										end
									elseif (Enum <= 110) then
										local A;
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										do
											return Stk[A], Stk[A + 1];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									elseif (Enum > 111) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									else
										local A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Top));
									end
								elseif (Enum <= 115) then
									if (Enum <= 113) then
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
									elseif (Enum == 114) then
										local A;
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									else
										local A;
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										VIP = Inst[3];
									end
								elseif (Enum <= 117) then
									if (Enum > 116) then
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									else
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									end
								elseif (Enum > 118) then
									local A;
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
								end
							elseif (Enum <= 126) then
								if (Enum <= 122) then
									if (Enum <= 120) then
										local A;
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									elseif (Enum > 121) then
										if (Stk[Inst[2]] <= Inst[4]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									else
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
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
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									end
								elseif (Enum <= 124) then
									if (Enum == 123) then
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										for Idx = Inst[2], Inst[3] do
											Stk[Idx] = nil;
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									else
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									end
								elseif (Enum > 125) then
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								else
									local Results;
									local Edx;
									local Results, Limit;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results, Limit = _R(Stk[A](Stk[A + 1]));
									Top = (Limit + A) - 1;
									Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results = {Stk[A](Unpack(Stk, A + 1, Top))};
									Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									VIP = Inst[3];
								end
							elseif (Enum <= 129) then
								if (Enum <= 127) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								elseif (Enum > 128) then
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								else
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return Stk[Inst[2]];
									end
								end
							elseif (Enum <= 131) then
								if (Enum == 130) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] / Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									VIP = Inst[3];
								else
									local Edx;
									local Results;
									local A;
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results = {Stk[A](Stk[A + 1])};
									Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum > 132) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 146) then
							if (Enum <= 139) then
								if (Enum <= 136) then
									if (Enum <= 134) then
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if (Inst[2] < Stk[Inst[4]]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									elseif (Enum > 135) then
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
											if (Mvm[1] == 240) then
												Indexes[Idx - 1] = {Stk,Mvm[3]};
											else
												Indexes[Idx - 1] = {Upvalues,Mvm[3]};
											end
											Lupvals[#Lupvals + 1] = Indexes;
										end
										Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
									else
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if not Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum <= 137) then
									local B;
									local T;
									local A;
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									T = Stk[A];
									B = Inst[3];
									for Idx = 1, B do
										T[Idx] = Stk[A + Idx];
									end
								elseif (Enum == 138) then
									local A = Inst[2];
									local Index = Stk[A];
									local Step = Stk[A + 2];
									if (Step > 0) then
										if (Index > Stk[A + 1]) then
											VIP = Inst[3];
										else
											Stk[A + 3] = Index;
										end
									elseif (Index < Stk[A + 1]) then
										VIP = Inst[3];
									else
										Stk[A + 3] = Index;
									end
								else
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								end
							elseif (Enum <= 142) then
								if (Enum <= 140) then
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum > 141) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									local A;
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 144) then
								if (Enum == 143) then
									Env[Inst[3]] = Stk[Inst[2]];
								elseif (Stk[Inst[2]] <= Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 145) then
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							else
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
							end
						elseif (Enum <= 153) then
							if (Enum <= 149) then
								if (Enum <= 147) then
									local A;
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								elseif (Enum == 148) then
									local A;
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 151) then
								if (Enum > 150) then
									local A;
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A], Stk[A + 1];
									end
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] == Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum > 152) then
								local A;
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								do
									return Unpack(Stk, A, Top);
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							else
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 156) then
							if (Enum <= 154) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 155) then
								if (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 158) then
							if (Enum > 157) then
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							else
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						elseif (Enum == 159) then
							local A;
							A = Inst[2];
							Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]]();
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Stk[Inst[2]] == Inst[4]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 187) then
						if (Enum <= 173) then
							if (Enum <= 166) then
								if (Enum <= 163) then
									if (Enum <= 161) then
										local K;
										local B;
										local A;
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										B = Inst[3];
										K = Stk[B];
										for Idx = B + 1, Inst[4] do
											K = K .. Stk[Idx];
										end
										Stk[Inst[2]] = K;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
									elseif (Enum == 162) then
										local A = Inst[2];
										local C = Inst[4];
										local CB = A + 2;
										local Result = {Stk[A](Stk[A + 1], Stk[CB])};
										for Idx = 1, C do
											Stk[CB + Idx] = Result[Idx];
										end
										local R = Result[1];
										if R then
											Stk[CB] = R;
											VIP = Inst[3];
										else
											VIP = VIP + 1;
										end
									else
										local A;
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return Stk[Inst[2]];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									end
								elseif (Enum <= 164) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] / Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] % Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Inst[2] < Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 165) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
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
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum <= 169) then
								if (Enum <= 167) then
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 168) then
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local B;
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum <= 171) then
								if (Enum == 170) then
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									B = Stk[Inst[4]];
									if not B then
										VIP = VIP + 1;
									else
										Stk[Inst[2]] = B;
										VIP = Inst[3];
									end
								else
									local B;
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum > 172) then
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							else
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
								end
							end
						elseif (Enum <= 180) then
							if (Enum <= 176) then
								if (Enum <= 174) then
									local Results;
									local Edx;
									local Results, Limit;
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results, Limit = _R(Stk[A](Stk[A + 1]));
									Top = (Limit + A) - 1;
									Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results = {Stk[A](Unpack(Stk, A + 1, Top))};
									Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									VIP = Inst[3];
								elseif (Enum == 175) then
									local A;
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								else
									local A;
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 178) then
								if (Enum == 177) then
									local Edx;
									local Results, Limit;
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results, Limit = _R(Stk[A](Stk[A + 1]));
									Top = (Limit + A) - 1;
									Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Top));
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum > 179) then
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A = Inst[2];
								local Results = {Stk[A](Stk[A + 1])};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							end
						elseif (Enum <= 183) then
							if (Enum <= 181) then
								local A = Inst[2];
								Stk[A] = Stk[A]();
							elseif (Enum > 182) then
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
							end
						elseif (Enum <= 185) then
							if (Enum > 184) then
								local A;
								local K;
								local B;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								B = Inst[3];
								K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
							else
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
							end
						elseif (Enum > 186) then
							local T;
							local K;
							local B;
							local A;
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							B = Inst[3];
							K = Stk[B];
							for Idx = B + 1, Inst[4] do
								K = K .. Stk[Idx];
							end
							Stk[Inst[2]] = K;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							T = Stk[A];
							B = Inst[3];
							for Idx = 1, B do
								T[Idx] = Stk[A + Idx];
							end
						else
							local A;
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]]();
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 200) then
						if (Enum <= 193) then
							if (Enum <= 190) then
								if (Enum <= 188) then
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								elseif (Enum > 189) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
								else
									local A;
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] ~= Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 191) then
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							elseif (Enum > 192) then
								Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							end
						elseif (Enum <= 196) then
							if (Enum <= 194) then
								local B;
								local A;
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							elseif (Enum == 195) then
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								Stk[Inst[2]] = not Stk[Inst[3]];
							end
						elseif (Enum <= 198) then
							if (Enum > 197) then
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							else
								local A;
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum > 199) then
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							for Idx = Inst[2], Inst[3] do
								Stk[Idx] = nil;
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A = Inst[2];
							do
								return Unpack(Stk, A, Top);
							end
						end
					elseif (Enum <= 207) then
						if (Enum <= 203) then
							if (Enum <= 201) then
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							elseif (Enum == 202) then
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 205) then
							if (Enum == 204) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							elseif (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 206) then
							local A;
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A]();
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
						else
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
						end
					elseif (Enum <= 210) then
						if (Enum <= 208) then
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 209) then
							local A;
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A = Inst[2];
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Stk[Inst[4]]];
						end
					elseif (Enum <= 212) then
						if (Enum == 211) then
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
						else
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
						end
					elseif (Enum > 213) then
						local A;
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						if not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						local A;
						Stk[Inst[2]] = Stk[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A]();
						VIP = VIP + 1;
						Inst = Instr[VIP];
						for Idx = Inst[2], Inst[3] do
							Stk[Idx] = nil;
						end
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Env[Inst[3]] = Stk[Inst[2]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A]();
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Env[Inst[3]] = Stk[Inst[2]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
					end
				elseif (Enum <= 322) then
					if (Enum <= 268) then
						if (Enum <= 241) then
							if (Enum <= 227) then
								if (Enum <= 220) then
									if (Enum <= 217) then
										if (Enum <= 215) then
											Env[Inst[3]] = Stk[Inst[2]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3] ~= 0;
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Env[Inst[3]] = Stk[Inst[2]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3] ~= 0;
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Env[Inst[3]] = Stk[Inst[2]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
										elseif (Enum == 216) then
											local B;
											local A;
											Stk[Inst[2]] = Stk[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A] = Stk[A]();
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											B = Stk[Inst[3]];
											Stk[A + 1] = B;
											Stk[A] = B[Inst[4]];
										else
											local B;
											local A;
											Env[Inst[3]] = Stk[Inst[2]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											B = Stk[Inst[3]];
											Stk[A + 1] = B;
											Stk[A] = B[Inst[4]];
										end
									elseif (Enum <= 218) then
										local A;
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									elseif (Enum == 219) then
										local Edx;
										local Results, Limit;
										local B;
										local A;
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Results, Limit = _R(Stk[A](Stk[A + 1]));
										Top = (Limit + A) - 1;
										Edx = 0;
										for Idx = A, Top do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Top));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									else
										local K;
										local B;
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										B = Inst[3];
										K = Stk[B];
										for Idx = B + 1, Inst[4] do
											K = K .. Stk[Idx];
										end
										Stk[Inst[2]] = K;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
									end
								elseif (Enum <= 223) then
									if (Enum <= 221) then
										local A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									elseif (Enum > 222) then
										local Results;
										local Edx;
										local Results, Limit;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Results, Limit = _R(Stk[A](Stk[A + 1]));
										Top = (Limit + A) - 1;
										Edx = 0;
										for Idx = A, Top do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Results = {Stk[A](Unpack(Stk, A + 1, Top))};
										Edx = 0;
										for Idx = A, Inst[4] do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										VIP = Inst[3];
									else
										local Edx;
										local Results;
										local A;
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Results = {Stk[A](Stk[A + 1])};
										Edx = 0;
										for Idx = A, Inst[4] do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										VIP = Inst[3];
									end
								elseif (Enum <= 225) then
									if (Enum == 224) then
										local A;
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = #Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if (Inst[2] < Stk[Inst[4]]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									else
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
								elseif (Enum > 226) then
									local A = Inst[2];
									Stk[A](Stk[A + 1]);
								else
									local A;
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 234) then
								if (Enum <= 230) then
									if (Enum <= 228) then
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									elseif (Enum > 229) then
										local B;
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if not Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									else
										local A;
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
									end
								elseif (Enum <= 232) then
									if (Enum > 231) then
										local A;
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										VIP = Inst[3];
									else
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									end
								elseif (Enum == 233) then
									local A;
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
								else
									Upvalues[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 237) then
								if (Enum <= 235) then
									local K;
									local B;
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									B = Inst[3];
									K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
								elseif (Enum == 236) then
									local A;
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								else
									Stk[Inst[2]] = Inst[3] / Stk[Inst[4]];
								end
							elseif (Enum <= 239) then
								if (Enum > 238) then
									local A;
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
								end
							elseif (Enum > 240) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return Stk[Inst[2]];
								end
							else
								Stk[Inst[2]] = Stk[Inst[3]];
							end
						elseif (Enum <= 254) then
							if (Enum <= 247) then
								if (Enum <= 244) then
									if (Enum <= 242) then
										local B;
										local A;
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
									elseif (Enum == 243) then
										local B;
										local T;
										local A;
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										T = Stk[A];
										B = Inst[3];
										for Idx = 1, B do
											T[Idx] = Stk[A + Idx];
										end
									else
										local A;
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = not Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									end
								elseif (Enum <= 245) then
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								elseif (Enum > 246) then
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
								end
							elseif (Enum <= 250) then
								if (Enum <= 248) then
									local B;
									local T;
									local A;
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									T = Stk[A];
									B = Inst[3];
									for Idx = 1, B do
										T[Idx] = Stk[A + Idx];
									end
								elseif (Enum == 249) then
									local B;
									local A;
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									local A = Inst[2];
									local Results, Limit = _R(Stk[A](Stk[A + 1]));
									Top = (Limit + A) - 1;
									local Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								end
							elseif (Enum <= 252) then
								if (Enum == 251) then
									local Edx;
									local Results, Limit;
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Results, Limit = _R(Stk[A](Stk[A + 1]));
									Top = (Limit + A) - 1;
									Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Top));
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								else
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								end
							elseif (Enum == 253) then
								local K;
								local B;
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
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
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								B = Inst[3];
								K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 261) then
							if (Enum <= 257) then
								if (Enum <= 255) then
									local A;
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								elseif (Enum == 256) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] < Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum <= 259) then
								if (Enum > 258) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum == 260) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Top)));
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								local B;
								local A;
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								do
									return Stk[A], Stk[A + 1];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							end
						elseif (Enum <= 264) then
							if (Enum <= 262) then
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							elseif (Enum > 263) then
								local A;
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							else
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 266) then
							if (Enum == 265) then
								do
									return Stk[Inst[2]]();
								end
							else
								local Edx;
								local Results, Limit;
								local B;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
								Top = (Limit + A) - 1;
								Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Top));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							end
						elseif (Enum == 267) then
							local B = Inst[3];
							local K = Stk[B];
							for Idx = B + 1, Inst[4] do
								K = K .. Stk[Idx];
							end
							Stk[Inst[2]] = K;
						else
							do
								return;
							end
						end
					elseif (Enum <= 295) then
						if (Enum <= 281) then
							if (Enum <= 274) then
								if (Enum <= 271) then
									if (Enum <= 269) then
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										for Idx = Inst[2], Inst[3] do
											Stk[Idx] = nil;
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]];
									elseif (Enum == 270) then
										local A;
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
									else
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]]();
									end
								elseif (Enum <= 272) then
									local A;
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = #Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] == Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 273) then
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] ~= Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									Upvalues[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum <= 277) then
								if (Enum <= 275) then
									local K;
									local B;
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									B = Inst[3];
									K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A], Stk[A + 1];
									end
								elseif (Enum > 276) then
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local B;
									local T;
									local A;
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									T = Stk[A];
									B = Inst[3];
									for Idx = 1, B do
										T[Idx] = Stk[A + Idx];
									end
								end
							elseif (Enum <= 279) then
								if (Enum > 278) then
									if (Stk[Inst[2]] < Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A], Stk[A + 1];
									end
								end
							elseif (Enum > 280) then
								local K;
								local B;
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								B = Inst[3];
								K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
							else
								local Edx;
								local Results, Limit;
								local A;
								A = Inst[2];
								Results, Limit = _R(Stk[A](Stk[A + 1]));
								Top = (Limit + A) - 1;
								Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Top));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 288) then
							if (Enum <= 284) then
								if (Enum <= 282) then
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								elseif (Enum > 283) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								else
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								end
							elseif (Enum <= 286) then
								if (Enum > 285) then
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum > 287) then
								local Edx;
								local Results, Limit;
								local B;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results, Limit = _R(Stk[A](Stk[A + 1]));
								Top = (Limit + A) - 1;
								Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								do
									return Unpack(Stk, A, Top);
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 291) then
							if (Enum <= 289) then
								local A;
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							elseif (Enum > 290) then
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
								Env[Inst[3]] = Stk[Inst[2]];
							end
						elseif (Enum <= 293) then
							if (Enum == 292) then
								local A = Inst[2];
								local B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							else
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
							end
						elseif (Enum > 294) then
							local B;
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A;
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 308) then
						if (Enum <= 301) then
							if (Enum <= 298) then
								if (Enum <= 296) then
									Stk[Inst[2]]();
								elseif (Enum > 297) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									VIP = Inst[3];
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] == Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 299) then
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = #Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Inst[2] < Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 300) then
								local A = Inst[2];
								local Cls = {};
								for Idx = 1, #Lupvals do
									local List = Lupvals[Idx];
									for Idz = 0, #List do
										local Upv = List[Idz];
										local NStk = Upv[1];
										local DIP = Upv[2];
										if ((NStk == Stk) and (DIP >= A)) then
											Cls[DIP] = NStk[DIP];
											Upv[1] = Cls;
										end
									end
								end
							else
								local A;
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 304) then
							if (Enum <= 302) then
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							elseif (Enum == 303) then
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return Stk[Inst[2]];
								end
							else
								local A;
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								VIP = Inst[3];
							end
						elseif (Enum <= 306) then
							if (Enum > 305) then
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							else
								local B;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							end
						elseif (Enum > 307) then
							local A;
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]]();
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum <= 315) then
						if (Enum <= 311) then
							if (Enum <= 309) then
								Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
							elseif (Enum > 310) then
								Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
							else
								local A = Inst[2];
								local T = Stk[A];
								local B = Inst[3];
								for Idx = 1, B do
									T[Idx] = Stk[A + Idx];
								end
							end
						elseif (Enum <= 313) then
							if (Enum == 312) then
								local Results;
								local Edx;
								local Results, Limit;
								local B;
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results, Limit = _R(Stk[A](Stk[A + 1]));
								Top = (Limit + A) - 1;
								Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results = {Stk[A](Unpack(Stk, A + 1, Top))};
								Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								VIP = Inst[3];
							else
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum > 314) then
							local Edx;
							local Limit;
							local Results;
							local A;
							A = Inst[2];
							Results = {Stk[A]()};
							Limit = Inst[4];
							Edx = 0;
							for Idx = A, Limit do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
						else
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 318) then
						if (Enum <= 316) then
							if (Stk[Inst[2]] > Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = VIP + Inst[3];
							end
						elseif (Enum == 317) then
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 320) then
						if (Enum == 319) then
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
						else
							local K;
							local B;
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							B = Inst[3];
							K = Stk[B];
							for Idx = B + 1, Inst[4] do
								K = K .. Stk[Idx];
							end
							Stk[Inst[2]] = K;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							B = Stk[Inst[4]];
							if B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						end
					elseif (Enum == 321) then
						local Edx;
						local Results, Limit;
						local A;
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A]();
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
						Top = (Limit + A) - 1;
						Edx = 0;
						for Idx = A, Top do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Top)));
						Top = (Limit + A) - 1;
						Edx = 0;
						for Idx = A, Top do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Top));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						VIP = Inst[3];
					else
						Stk[Inst[2]] = Upvalues[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Upvalues[Inst[3]] = Stk[Inst[2]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Upvalues[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						do
							return Stk[Inst[2]];
						end
						VIP = VIP + 1;
						Inst = Instr[VIP];
						do
							return;
						end
					end
				elseif (Enum <= 376) then
					if (Enum <= 349) then
						if (Enum <= 335) then
							if (Enum <= 328) then
								if (Enum <= 325) then
									if (Enum <= 323) then
										local B;
										local A;
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Upvalues[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if (Stk[Inst[2]] ~= Inst[4]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									elseif (Enum > 324) then
										local A = Inst[2];
										local Results, Limit = _R(Stk[A]());
										Top = (Limit + A) - 1;
										local Edx = 0;
										for Idx = A, Top do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
									else
										local T;
										local B;
										local A;
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = {};
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Inst[4];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A]();
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A] = Stk[A](Stk[A + 1]);
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										T = Stk[A];
										B = Inst[3];
										for Idx = 1, B do
											T[Idx] = Stk[A + Idx];
										end
									end
								elseif (Enum <= 326) then
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								elseif (Enum > 327) then
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								else
									local A = Inst[2];
									local Results = {Stk[A]()};
									local Limit = Inst[4];
									local Edx = 0;
									for Idx = A, Limit do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								end
							elseif (Enum <= 331) then
								if (Enum <= 329) then
									local A;
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								elseif (Enum > 330) then
									local A;
									A = Inst[2];
									Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								else
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum <= 333) then
								if (Enum == 332) then
									local A;
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] < Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum > 334) then
								local Edx;
								local Results, Limit;
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results, Limit = _R(Stk[A](Stk[A + 1]));
								Top = (Limit + A) - 1;
								Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Top));
							else
								Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
							end
						elseif (Enum <= 342) then
							if (Enum <= 338) then
								if (Enum <= 336) then
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Upvalues[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								elseif (Enum == 337) then
									local A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum <= 340) then
								if (Enum == 339) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								else
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								end
							elseif (Enum == 341) then
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 345) then
							if (Enum <= 343) then
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return Stk[Inst[2]];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							elseif (Enum > 344) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 347) then
							if (Enum > 346) then
								local A;
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							else
								local A;
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum == 348) then
							do
								return Stk[Inst[2]];
							end
						else
							local Edx;
							local Results;
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Results = {Stk[A](Stk[A + 1])};
							Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							VIP = Inst[3];
						end
					elseif (Enum <= 362) then
						if (Enum <= 355) then
							if (Enum <= 352) then
								if (Enum <= 350) then
									local A;
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] < Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 351) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = #Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return Stk[Inst[2]];
									end
								end
							elseif (Enum <= 353) then
								local Results;
								local Edx;
								local Results, Limit;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results, Limit = _R(Stk[A]());
								Top = (Limit + A) - 1;
								Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results = {Stk[A](Unpack(Stk, A + 1, Top))};
								Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								VIP = Inst[3];
							elseif (Enum == 354) then
								local K;
								local B;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								B = Inst[3];
								K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							else
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							end
						elseif (Enum <= 358) then
							if (Enum <= 356) then
								local A;
								local K;
								local B;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								B = Inst[3];
								K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return Stk[Inst[2]];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							elseif (Enum == 357) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return Stk[Inst[2]];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							else
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 360) then
							if (Enum > 359) then
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
							else
								local A;
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
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum > 361) then
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
						else
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if (Stk[Inst[2]] > Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = VIP + Inst[3];
							end
						end
					elseif (Enum <= 369) then
						if (Enum <= 365) then
							if (Enum <= 363) then
								Stk[Inst[2]] = Inst[3] ~= 0;
							elseif (Enum == 364) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = #Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								VIP = Inst[3];
							else
								local B;
								local A;
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 367) then
							if (Enum == 366) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								do
									return Unpack(Stk, A, Top);
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							end
						elseif (Enum == 368) then
							Stk[Inst[2]] = {};
						else
							local A;
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							do
								return Unpack(Stk, A, Top);
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum <= 372) then
						if (Enum <= 370) then
							local B;
							local A;
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
						elseif (Enum == 371) then
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						else
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if not Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 374) then
						if (Enum == 373) then
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
						else
							local B;
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum == 375) then
						local A = Inst[2];
						local T = Stk[A];
						for Idx = A + 1, Top do
							Insert(T, Stk[Idx]);
						end
					else
						local A;
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = {};
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
					end
				elseif (Enum <= 403) then
					if (Enum <= 389) then
						if (Enum <= 382) then
							if (Enum <= 379) then
								if (Enum <= 377) then
									local A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
								elseif (Enum == 378) then
									local A;
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] <= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum <= 380) then
								Stk[Inst[2]] = Inst[3];
							elseif (Enum > 381) then
								local A = Inst[2];
								local Step = Stk[A + 2];
								local Index = Stk[A] + Step;
								Stk[A] = Index;
								if (Step > 0) then
									if (Index <= Stk[A + 1]) then
										VIP = Inst[3];
										Stk[A + 3] = Index;
									end
								elseif (Index >= Stk[A + 1]) then
									VIP = Inst[3];
									Stk[A + 3] = Index;
								end
							else
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 385) then
							if (Enum <= 383) then
								local A;
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return Stk[Inst[2]];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							elseif (Enum > 384) then
								local A;
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							else
								Stk[Inst[2]] = Stk[Inst[3]] - Inst[4];
							end
						elseif (Enum <= 387) then
							if (Enum > 386) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							end
						elseif (Enum > 388) then
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						else
							Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
						end
					elseif (Enum <= 396) then
						if (Enum <= 392) then
							if (Enum <= 390) then
								local B;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								B = Stk[Inst[4]];
								if not B then
									VIP = VIP + 1;
								else
									Stk[Inst[2]] = B;
									VIP = Inst[3];
								end
							elseif (Enum > 391) then
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local B;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 394) then
							if (Enum == 393) then
								local A;
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum == 395) then
							local A;
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
						else
							local Edx;
							local Results, Limit;
							local A;
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
							Top = (Limit + A) - 1;
							Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Top));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							VIP = Inst[3];
						end
					elseif (Enum <= 399) then
						if (Enum <= 397) then
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
						elseif (Enum > 398) then
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]]();
							VIP = VIP + 1;
							Inst = Instr[VIP];
							for Idx = Inst[2], Inst[3] do
								Stk[Idx] = nil;
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							do
								return Unpack(Stk, A, Top);
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum <= 401) then
						if (Enum == 400) then
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						else
							local A;
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum > 402) then
						local Edx;
						local Results;
						local A;
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Results = {Stk[A](Stk[A + 1])};
						Edx = 0;
						for Idx = A, Inst[4] do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
						VIP = VIP + 1;
						Inst = Instr[VIP];
						VIP = Inst[3];
					else
						local A = Inst[2];
						do
							return Unpack(Stk, A, A + Inst[3]);
						end
					end
				elseif (Enum <= 416) then
					if (Enum <= 409) then
						if (Enum <= 406) then
							if (Enum <= 404) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 405) then
								Stk[Inst[2]] = Upvalues[Inst[3]];
							else
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]];
							end
						elseif (Enum <= 407) then
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 408) then
							local B;
							local A;
							A = Inst[2];
							B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
						else
							local B;
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							do
								return Unpack(Stk, A, Top);
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum <= 412) then
						if (Enum <= 410) then
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
						elseif (Enum == 411) then
							local A;
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
						else
							local A;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 414) then
						if (Enum == 413) then
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
						else
							local B;
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum > 415) then
						local B = Stk[Inst[4]];
						if not B then
							VIP = VIP + 1;
						else
							Stk[Inst[2]] = B;
							VIP = Inst[3];
						end
					else
						Stk[Inst[2]][Inst[3]] = Inst[4];
					end
				elseif (Enum <= 423) then
					if (Enum <= 419) then
						if (Enum <= 417) then
							local Edx;
							local Results, Limit;
							local B;
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
							Top = (Limit + A) - 1;
							Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Top));
						elseif (Enum == 418) then
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
						else
							local A;
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
						end
					elseif (Enum <= 421) then
						if (Enum == 420) then
							if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum == 422) then
						local A;
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
					elseif (Inst[2] < Stk[Inst[4]]) then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 426) then
					if (Enum <= 424) then
						local A;
						Stk[Inst[2]] = Inst[3] ~= 0;
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Env[Inst[3]] = Stk[Inst[2]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]]();
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						do
							return Stk[Inst[2]]();
						end
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						do
							return Unpack(Stk, A, Top);
						end
						VIP = VIP + 1;
						Inst = Instr[VIP];
						do
							return;
						end
					elseif (Enum > 425) then
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Inst[4];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
					else
						local A;
						Stk[Inst[2]] = Stk[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A]();
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						if (Stk[Inst[2]] ~= Inst[4]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					end
				elseif (Enum <= 428) then
					if (Enum == 427) then
						local A;
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Inst[3];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						if (Stk[Inst[2]] == Inst[4]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						local A;
						A = Inst[2];
						Stk[A] = Stk[A]();
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						if (Stk[Inst[2]] < Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					end
				elseif (Enum == 429) then
					local A;
					Stk[Inst[2]] = Env[Inst[3]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Inst[3];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Inst[3];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Inst[3];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					A = Inst[2];
					Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Env[Inst[3]] = Stk[Inst[2]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Env[Inst[3]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					VIP = Inst[3];
				else
					local A;
					Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Inst[3] / Stk[Inst[4]];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Inst[3];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Stk[Inst[2]] = Inst[3];
					VIP = VIP + 1;
					Inst = Instr[VIP];
					A = Inst[2];
					Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
					VIP = VIP + 1;
					Inst = Instr[VIP];
					Env[Inst[3]] = Stk[Inst[2]];
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!DC012Q00030C3Q005343524950545F5449544C45030C3Q00F09F94B04D41584920485542030E3Q005343524950545F56455253494F4E03043Q0076322E3203083Q004755495F4E414D4503073Q004D617869487562030D3Q0054454C454752414D5F4C494E4B03153Q00682Q7470733A2Q2F742E6D652F4D4158495F48554203073Q00506C617965727303043Q0067616D65030A3Q0047657453657276696365030A3Q0052756E5365727669636503103Q0055736572496E70757453657276696365030A3Q0047756953657276696365030B3Q00482Q747053657276696365030C3Q0054772Q656E5365727669636503113Q005265706C69636174656453746F72616765030B3Q00434F4E4649475F46494C4503143Q006D6178692D6875622D636F6E6669672E6A736F6E030E3Q00434F4E4649475F56455253494F4E027Q0040030F3Q0053452Q4C5F53544154455F46494C4503183Q006D6178692D6875622D73652Q6C2D73746174652E6A736F6E030A3Q0055694C616E677561676503023Q00727503093Q004C6F63616C654C6962030E3Q006C6F63616C6542696E64696E677303113Q006372656469747341626F75744C6162656C030F3Q0063726564697473546742752Q746F6E030B3Q004B45595F574542482Q4F4B03793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D6803133Q00444953434F52445F434F4E4649475F46494C4503153Q006D6178692D6875622D646973636F72642E6A736F6E03123Q0055736572446973636F7264576562682Q6F6B034Q0003153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E75746573026Q00244003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F7003063Q00706C6179657203093Q00706C6179657247756903043Q0067656E7603063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47030C3Q00656E73757265506C61796572030B3Q004661726D456E61626C6564030A3Q006661726D54687265616403093Q006661726D52756E4964028Q00030D3Q006661726D54696D65546F74616C030F3Q006661726D54696D655374617274656403123Q0074656C65706F7274436F2Q6E656374696F6E03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503093Q006661726D506861736503043Q0069646C65030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403063Q00484F544B455903043Q00456E756D03073Q004B6579436F64652Q033Q00456E64030F3Q0070656E64696E675072657653746F70030B3Q004D61786948756253746F70030E3Q006661726D436865636B506175736503123Q0073686F756C644661726D436F6E74696E7565030D3Q00697343616E63656C452Q726F7203103Q0063616D657261436F2Q6E656374696F6E030E3Q00612Q706C79496E7669736963616D030E3Q0073746F7043616D6572614C2Q6F70030D3Q00726573746F726543616D657261030F3Q00737461727443616D6572614C2Q6F70030E3Q00434F2Q4C4543545F524144495553026Q004E40030E3Q0054656C65706F727448656967687403133Q0053746F6E6554656C65706F7274486569676874026Q000C40030C3Q0069676E6F72656444726F7073030F3Q0063616368656444726F70436F756E7403043Q00564B5F46025Q0080514003073Q00557365464B657903083Q00557365436C69636B03113Q004C656769744D6F75736543617074757265030C3Q004F72626974456E61626C6564030B3Q0041696D417454617267657403113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B54726164657303103Q0052656E646572336444697361626C656403123Q004175746F52656E64657233644F6E4661726D03123Q00426C61636B5363722Q656E4F7665726C617903123Q0072656E64657233644265666F72654661726D03123Q0072656E64657233644661726D41637469766503183Q0072656E64657233644661726D4E2Q656473526573746F7265030E3Q00626C61636B5363722Q656E47756903113Q0073657452656E6465723364546F2Q676C6503143Q0072656E6465723364546F2Q676C6553696C656E74030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A65026Q00494003113Q00426C6F636B65645A6F6E6543656E74657203153Q00626C6F636B65645A6F6E6556697375616C5061727403133Q00424C4F434B45445F5A4F4E455F464F4C444552030C3Q004D6178694875625A6F6E6573030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C026Q003440030F3Q0053652Q6C4261746368416D6F756E74025Q004CCD4003143Q0053652Q6C436F636F6E75745468726573686F6C64024Q008093C140030D3Q0053452Q4C5F574F524C445F4944022Q008081CBE4E941030D3Q004641524D5F574F524C445F4944022Q00105C7A23F24103123Q0053452Q4C5F574149545F41465445525F5450026Q001440030A3Q0053452Q4C5F4954454D5303073Q004176616361646F03073Q00436F636F6E757403093Q00436163616F4265616E03053Q00412Q706C6503043Q00436F726E03053Q004C656D6F6E03113Q0073652Q73696F6E53746F6E6544726F707303113Q0073652Q73696F6E54722Q65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E6564030C3Q006661726D5761726E696E6773030D3Q006C6173745761726E696E67417403103Q0073652Q73696F6E54722Q6544726F7073030D3Q004F726269744469616D65746572026Q002C40030A3Q004F7262697453702Q6564029A5Q99F13F03103Q004661726D54722Q6573456E61626C656403113Q004661726D53746F6E6573456E61626C6564030E3Q005461726765745069636B4D6F646503073Q006E656172657374030C3Q0054656C65706F72744D6F646503073Q00696E7374616E7403103Q0054656C65706F72745374657053697A65026Q00284003113Q0054656C65706F72745374657044656C617902B81E85EB51B8AE3F030B3Q00412Q7461636B44656C6179026Q33C33F03113Q0044454641554C545F5A4F4E455F53495A4503103Q00426C6F636B65645A6F6E65734C697374030A3Q00457370456E61626C656403083Q0045737054722Q657303093Q0045737053746F6E6573030A3Q00457370506C6179657273030C3Q004573705265736F7572636573030A3Q00457370447261676F6E73030A3Q004573705472616365727303083Q004573704E616D6573030B3Q004573705465787453697A6503093Q00457370436F6C6F727303053Q0074722Q6573025Q00C06840025Q0040664003063Q0073746F6E6573025Q00806140025Q00806640025Q00E06F4003073Q00706C6179657273025Q00806B40026Q00544003093Q007265736F7572636573026Q00644003073Q00647261676F6E7303063Q00747261636572030C3Q006C617374412Q7461636B4174030D3Q004D6178694875624553504C6962030D3Q007A6F6E654C6973744C6162656C03123Q007A6F6E65734C697374436F6E7461696E6572030E3Q0044454641554C545F55495F504F5303053Q005544696D322Q033Q006E6577026Q003040026Q00E03F025Q00E070C0030A3Q0073617665645569506F73030C3Q007363722Q656E477569526566030A3Q0068692Q64656E4775697303133Q00736166654D6F6465436F2Q6E656374696F6E73030B3Q0054524144455F48494E545303053Q00747261646503073Q0074726164696E67030A3Q0074726164656F2Q666572030C3Q0074726164657265717565737403083Q0065786368616E676503043Q0073776170030A3Q006F72626974416E676C6503093Q006D6F75736548656C64030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F7573655903143Q00656E73757265426C61636B5363722Q656E47756903183Q00757064617465426C61636B5363722Q656E4F7665726C617903123Q00612Q706C7952656E64657233645374617465030E3Q00746F2Q676C6552656E646572336403133Q006F6E4661726D52656E6465723364537461727403123Q006F6E4661726D52656E646572336453746F70030F3Q00636C65616E757052656E646572336403103Q0063616E557365436F6E66696746696C6503133Q0073617665436F6E6669675363686564756C6564030F3Q0073617665436F6E666967546F6B656E030C3Q006D61696E4672616D65526566030F3Q0072656164436F6E6669675461626C6503103Q007772697465436F6E6669675461626C6503123Q0073657269616C697A65457370436F6C6F727303193Q0073657269616C697A65426C6F636B65645A6F6E65734C697374031B3Q00646573657269616C697A65426C6F636B65645A6F6E65734C69737403123Q006275696C64436F6E6669675061796C6F6164030A3Q0073617665436F6E66696703103Q007061746368436F6E6669675461626C6503123Q007363686564756C6553617665436F6E666967030F3Q00666C75736853617665436F6E666967030D3Q006C6F616453652Q6C537461746503133Q0068617350656E64696E6753652Q6C5374617465030D3Q007361766553652Q6C5374617465030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F6703123Q0066696E616C697A6553652Q6C526573756D6503103Q006578656375746553652Q6C4974656D73031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F747374726170030A3Q006C6F6164436F6E666967030F3Q00707573684661726D5761726E696E6703103Q00636C6561724661726D5761726E696E6703133Q006765744661726D5761726E696E67735465787403183Q0067657454656C65706F7274486569676874466F724B696E64030F3Q006765744661726D4D6F646554657874030F3Q00535455434B5F465F5345434F4E4453026Q001040030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365030B3Q00736561726368416E676C65030C3Q00736561726368526164697573030C3Q00706174726F6C506F696E7473030B3Q00706174726F6C496E646578026Q00F03F030B3Q00687562506F736974696F6E030C3Q004855425F574149545F4D494E026Q000840030C3Q004855425F574149545F4D4158026Q002040030F3Q004855425F4E4541525F524144495553026Q002E40030F3Q006C61737453652Q6C436865636B4174030E3Q0073652Q6C496E50726F6772652Q73030F3Q006D616E75616C53652Q6C546F6B656E03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006765744661726D446973636F7264576562682Q6F6B03113Q0073617665446973636F7264436F6E666967030A3Q0050484153455F5445585403103Q00D0BED0B6D0B8D0B4D0B0D0BDD0B8D0B503063Q00736561726368030A3Q00D0BFD0BED0B8D181D0BA03043Q006D696E65030C3Q00D0B4D0BED0B1D18BD187D0B003043Q007761697403133Q00D0B6D0B4D191D0BC20D0B4D180D0BED0BFD18B03073Q00636F2Q6C65637403083Q00D181D0B1D0BED18003043Q0073652Q6C030E3Q00D0BFD180D0BED0B4D0B0D0B6D0B02Q033Q00687562030A3Q00D186D0B5D0BDD182D18003063Q0074726176656C03143Q00D0BFD183D182D18C20D0BA20D0BDD0BED0B4D0B503173Q00676574576F726B73706163654D6F64756C655061746873030A3Q006C6F61644573704C696203103Q004D6178694875624368616E67656C6F6703103Q006C6F61644368616E67656C6F674C6962030A3Q0072656672657368457370030D3Q006C6F61644C6F63616C654C696203013Q004C030E3Q0072656769737465724C6F63616C65030A3Q006765745461624465667303103Q007265667265736850686173655465787403173Q00757064617465446973636F72645374617475735465787403163Q007570646174654372656469747341626F75745465787403123Q00612Q706C794D6178694875624C6F63616C65030D3Q0073657455694C616E677561676503143Q0067657454656C65706F7274537061776E5061727403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C030B3Q0072656C65617365464B657903103Q0072656C656173654D6F757365486F6C6403133Q0073746F704368617261637465724D6F74696F6E03163Q00676574426C6F636B65645A6F6E6548616C6653697A6503143Q00676574426C6F636B65645A6F6E654D696E4D617803143Q006E6F726D616C697A65426C6F636B65645A6F6E6503193Q006E6F726D616C697A65426C6F636B65645A6F6E65734C69737403123Q006973506F73496E426C6F636B65645A6F6E6503113Q0072656D6F7665426C6F636B65645A6F6E6503163Q00612Q64426C6F636B65645A6F6E654174506C6179657203113Q00636C656172426C6F636B65645A6F6E6573030E3Q006372656174655A6F6E654361726403123Q0072656275696C645A6F6E65734C697374554903133Q0069734E6F6465496E426C6F636B65645A6F6E6503173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00757064617465426C6F636B65645A6F6E6556697375616C03163Q00736574426C6F636B65645A6F6E654174506C6179657203153Q00612Q706C79487270434672616D65496E7374616E7403143Q0074656C65706F7274487270546F496E7374616E7403123Q0074656C65706F7274487270546F5374657073030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C655761697403183Q00696E74652Q7275707469626C6557616974466F7253652Q6C03123Q0063617074757265487562506F736974696F6E030E3Q00676574487562506F736974696F6E03093Q0069734E656172487562030D3Q0074656C65706F7274546F487562030B3Q00687562526573745761697403143Q0072657475726E546F48756241667465724E6F6465030C3Q0073686F756C645072652Q734603063Q007072652Q734603113Q006D6F76654D6F757365546F5363722Q656E030B3Q00686F6C644D6F757365417403073Q00636C69636B4174030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73030F3Q0067657450617274506F736974696F6E030F3Q0067657441696D5363722Q656E506F73030D3Q006973546172676574416C69766503113Q00676574546172676574486974626F786573030F3Q0067657454617267657443656E746572030F3Q006765745461726765744865616C7468030B3Q0069734E6F6465416C697665030D3Q006765744E6F64654865616C7468030A3Q0072657365744175746F46030B3Q007570646174654175746F46030B3Q00676574486974626F786573030E3Q00676574436F2Q6C65637450617274030D3Q006765744E6F646543656E746572030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473030E3Q007069636B4265737454617267657403133Q0072656275696C64506174726F6C506F696E7473030E3Q0074656C65706F727453656172636803103Q0044524F505F4D4F44454C5F48494E545303093Q00462Q6F644D6F64656C03123Q00572Q6F645265736F75726365734D6F64656C03143Q00436F2Q7065725265736F75726365734D6F64656C03123Q004C6561665265736F75726365734D6F64656C030E3Q005265736F75726365734D6F64656C03133Q0069735265736F7572636544726F704D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C030D3Q00697344726F7049676E6F72656403113Q006D61726B44726F70436F2Q6C656374656403123Q00697356616C6964436F2Q6C65637444726F7003173Q0066696E6443616D6572615265736F7572636544726F7073030D3Q0066696E6444726F70734E656172030B3Q00636F2Q6C65637450617274030F3Q00636F2Q6C656374412Q6C44726F7073030A3Q00612Q7461636B50617274030F3Q0064726F707341726553652Q746C656403103Q0077616974416E645363616E44726F707303103Q006765744D696E65416E63686F72506F7303103Q0074656C65706F7274546F54617267657403083Q0069734F7572477569030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A656374030A3Q007363616E547261646573030D3Q00686964654F7468657247756973030A3Q00636C6561725461626C65030C3Q0073746F70536166654D6F6465030D3Q007374617274536166654D6F646503123Q006765745265736F7572636573466F6C64657203113Q006765745265736F75726365416D6F756E7403143Q0067657453652Q6C5472692Q676572416D6F756E74030D3Q006E2Q6564734175746F53652Q6C030E3Q006765744661726D5365636F6E6473030B3Q00682Q74705265717565737403123Q00706F7374446973636F7264576562682Q6F6B03103Q0073656E64446973636F7264456D62656403173Q006765745265736F75726365734F7665724F6E655465787403153Q0067657453652Q73696F6E53746174734669656C647303153Q006C6F674661726D53652Q73696F6E446973636F726403133Q0077616974466F7243686172616374657248727003083Q0073652Q6C57616974030D3Q0067657453652Q6C52656D6F746503163Q00676574576F726C6454656C65706F727452656D6F7465030D3Q00776F726C6454656C65706F727403103Q0073652Q6C5265736F757263654974656D030C3Q0072756E53652Q6C4379636C65030B3Q0072756E4175746F53652Q6C030D3Q0072756E4D616E75616C53652Q6C03103Q006D6179626552756E4175746F53652Q6C03123Q006D6179626552756E4661726D5265706F7274030E3Q0072756E5365617263685068617365030D3Q006B692Q6C4661726D4C2Q6F707303083Q0073746F704661726D030B3Q00736F6674436C65616E7570030A3Q0066752Q6C556E6C6F616403153Q004D617869487562546F2Q676C6552656E646572336403123Q004D6178694875625061746368436F6E66696703123Q004D617869487562466C757368436F6E66696703093Q0073746172744661726D030F3Q004D617869487562476574537461747303183Q004D6178694875625061757365466F72496E76656E746F7279031B3Q004D617869487562526573756D654166746572496E76656E746F727903043Q007479706503103Q004D6178694875624C6F63616C522Q6F7403063Q00737472696E6703113Q005F4D61786948756255494C69627261727903123Q004D6178694875624F2Q66696369616C52617703113Q004D61786948756252656D6F746542617365030F3Q004D6178694875625265706F4F6E6C7903083Q007265616466696C6503063Q00697366696C6503063Q00697061697273030F3Q006D6178692D6875622D75692E6C756103073Q00482Q747047657403053Q00652Q726F72033F3Q005B4D415849204855425D20554920D182D0BED0BBD18CD0BAD0BE20D18120D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD0BED0B3D0BE20D180D0B5D0BFD0BE03583Q005B4D415849204855425D20D09DD183D0B6D0B5D0BD206D6178692D6875622D75692E6C75612028D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD18BD0B920D180D0B5D0BFD0BE20D0B8D0BBD0B820776F726B737061636529030A3Q006C6F6164737472696E6703103Q00406D6178692D6875622D75692E6C756103173Q005B4D415849204855425D20554920636F6D70696C653A2003083Q00746F737472696E6703133Q005B4D415849204855425D2055492072756E3A20030C3Q004D61786948756255494C696203093Q0055495F4C41594F555403073Q0050414E454C5F57026Q00694003073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58026Q006B4003063Q00524F57335F59026Q006C4003063Q0046552Q4C5F57025Q00407A40030E3Q00534C494445525F50414E454C5F48030E3Q0053452Q53494F4E5F424F44595F59025Q00804140030D3Q00534C494445525F424F44595F59026Q004440030A3Q004D494E455F424F585F48025Q00C06540030D3Q00534C49444552535F424F585F48026Q005C40030A3Q00534146455F424F585F48026Q005640030D3Q00544F2Q474C455F595F53544550026Q004640030D3Q00534C494445525F595F5354455003183Q006275696C644D6178694875624368616E67656C6F6754616203163Q006275696C644D61786948756243726564697473546162030F3Q00687562422Q6F74737472612Q70656403103Q00622Q6F7473747261704D617869487562030D3Q006C61756E63684D617869487562030F3Q004D61786948756252656C61756E636803083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C6179657247756903053Q007072696E7403283Q005B4D415849204855425D20D0BCD0BED0B4D183D0BBD18C20D0B7D0B0D0B3D180D183D0B6D0B5D0BD03043Q007461736B03053Q0064656665720038042Q0012A93Q00023Q00124Q00013Q00124Q00043Q00124Q00033Q00124Q00063Q00124Q00053Q00124Q00083Q00124Q00073Q00124Q000A3Q00206Q000B00122Q000200098Q0002000200124Q00093Q00124Q000A3Q00206Q000B00122Q0002000C8Q0002000200124Q000C3Q00124Q000A3Q00206Q000B00122Q0002000D8Q0002000200124Q000D3Q00124Q000A3Q00206Q000B00122Q0002000E8Q0002000200124Q000E3Q00124Q000A3Q00206Q000B00122Q0002000F8Q0002000200124Q000F3Q00124Q000A3Q00206Q000B00122Q000200108Q0002000200124Q00103Q00124Q000A3Q00206Q000B00122Q000200118Q0002000200124Q00113Q00124Q00133Q00124Q00123Q00124Q00153Q00124Q00143Q00124Q00173Q00124Q00163Q00124Q00193Q00124Q00189Q003Q00124Q001A9Q003Q00124Q001B9Q003Q00124Q001C9Q003Q00124Q001D3Q00124Q001F3Q00124Q001E3Q00124Q00213Q00124Q00203Q00124Q00233Q00124Q00228Q00013Q00124Q00243Q00124Q00263Q00124Q00258Q00013Q00124Q00278Q00013Q00124Q00289Q003Q00124Q00299Q003Q00124Q002A9Q003Q00124Q002B3Q00124Q002C3Q00124A2Q01002D4Q0079012Q000200020026A03Q00580001002E0004603Q0058000100124A012Q002D4Q00B53Q0001000200128F3Q002B3Q0004603Q005A000100124A012Q002F3Q00128F3Q002B3Q000235016Q0012813Q00309Q003Q00124Q00319Q003Q00124Q00323Q00124Q00343Q00124Q00333Q00124Q00343Q00124Q00353Q00124Q00343Q00128F3Q00364Q00917Q00128F3Q00374Q00917Q00128F3Q00384Q00917Q00128F3Q00393Q00127C012Q003B3Q00128F3Q003A3Q00127C012Q003D3Q00128F3Q003C3Q00127C012Q00343Q00127B3Q003E3Q00124Q00343Q00124Q003F3Q00124Q00413Q00206Q004200206Q004300124Q00409Q003Q00124Q00443Q00124Q002C3Q00124A2Q01002B3Q0020482Q01000100452Q0079012Q000200020026A03Q00830001002E0004603Q0083000100124A012Q002B3Q002048014Q004500128F3Q00444Q006B016Q00128F3Q00463Q000235012Q00013Q00128F3Q00473Q000235012Q00023Q00128F3Q00484Q00917Q00128F3Q00493Q000235012Q00033Q00128F3Q004A3Q000235012Q00043Q00128F3Q004B3Q000235012Q00053Q00128F3Q004C3Q000235012Q00063Q00128B3Q004D3Q00124Q004F3Q00124Q004E3Q00124Q00153Q00124Q00503Q00124Q00523Q00124Q00519Q003Q00124Q00533Q00124Q00343Q00124Q00543Q00124Q00563Q00124Q00558Q00013Q00124Q00578Q00013Q00124Q00589Q003Q00124Q00599Q003Q00124Q005A8Q00013Q00124Q005B9Q003Q00124Q005C8Q00013Q00124Q005D9Q003Q00124Q005E8Q00013Q00124Q005F8Q00013Q00124Q00609Q003Q00124Q00619Q003Q00124Q00629Q003Q00124Q00639Q003Q00124Q00649Q003Q00124Q00659Q003Q00124Q00668Q00013Q00124Q00679Q003Q00124Q00689Q003Q00124Q00699Q003Q00124Q006A3Q00124Q006C3Q00124Q006B9Q003Q00124Q006D9Q003Q00124Q006E3Q00124Q00703Q00124Q006F8Q00013Q00124Q00713Q00124Q00733Q00124Q00723Q00124Q00753Q00124Q00743Q00124Q00773Q00124Q00763Q00124Q00793Q00124Q00783Q00124Q007B3Q00124Q007A3Q00124Q007D3Q00124Q007C8Q00063Q00122Q0001007F3Q00122Q000200803Q00122Q000300813Q00122Q000400823Q00127C010500833Q00127C010600844Q0036012Q0006000100128F3Q007E3Q0012D43Q00343Q00124Q00853Q00124Q00343Q00124Q00863Q00124Q00343Q00124Q00879Q003Q00124Q00889Q003Q00124Q00893Q00127C012Q00343Q00128F3Q008A3Q00127C012Q008C3Q00128F3Q008B3Q00127C012Q008E3Q00128F3Q008D4Q006B012Q00013Q00128F3Q008F4Q006B012Q00013Q00128F3Q00903Q00127C012Q00923Q00128F3Q00913Q00127C012Q00943Q00128F3Q00933Q00127C012Q00963Q00128F3Q00953Q00127C012Q00983Q00128F3Q00973Q00127C012Q009A3Q00128F3Q00993Q00127C012Q006C3Q00128F3Q009B4Q0070016Q00128F3Q009C4Q006B016Q00128F3Q009D4Q006B012Q00013Q00128F3Q009E4Q006B012Q00013Q00128F3Q009F4Q006B016Q00128F3Q00A04Q006B012Q00013Q00128F3Q00A14Q006B012Q00013Q00128F3Q00A24Q006B012Q00013Q00128F3Q00A34Q006B012Q00013Q00128F3Q00A43Q00127C012Q008C3Q00128F3Q00A54Q0070014Q00062Q00142Q0100033Q00122Q000200343Q00122Q000300A83Q00122Q000400A96Q000100030001001032012Q00A700012Q00142Q0100033Q00122Q000200AB3Q00122Q000300AC3Q00122Q000400AD6Q000100030001001032012Q00AA00012Q00142Q0100033Q00122Q000200AD3Q00122Q000300AF3Q00122Q000400B06Q000100030001001032012Q00AE00012Q00142Q0100033Q00122Q000200B23Q00122Q000300B23Q00122Q000400AD6Q000100030001001032012Q00B100012Q00142Q0100033Q00122Q000200AD3Q00122Q000300AB3Q00122Q0004004F6Q000100030001001032012Q00B300012Q00142Q0100033Q00122Q000200343Q00122Q000300A83Q00122Q000400A96Q000100030001001032012Q00B400010012923Q00A63Q00124Q00343Q00124Q00B59Q003Q00124Q00B69Q003Q00124Q00B79Q003Q00124Q00B83Q00124Q00BA3Q002073014Q00BB00122Q000100343Q00122Q000200BC3Q00122Q000300BD3Q00122Q000400BE8Q0004000200128F3Q00B94Q00917Q00128F3Q00BF4Q00917Q00128F3Q00C04Q0070016Q00128F3Q00C14Q0070016Q00128F3Q00C24Q0070012Q00063Q00127C2Q0100C43Q00127C010200C53Q00127C010300C63Q00127C010400C73Q00127C010500C83Q00127C010600C94Q0036012Q0006000100128F3Q00C33Q00127C012Q00343Q00128F3Q00CA4Q006B016Q00128F3Q00CB3Q00127C012Q00343Q00127C2Q0100343Q00128F000100CD3Q00128F3Q00CC3Q000235012Q00073Q00128F3Q00CE3Q000235012Q00083Q00128F3Q00CF3Q000235012Q00093Q00128F3Q00D03Q000235012Q000A3Q00128F3Q00D13Q000235012Q000B3Q00128F3Q00D23Q000235012Q000C3Q00128F3Q00D33Q000235012Q000D3Q00128F3Q00D43Q000235012Q000E3Q00122Q012Q00D59Q003Q00124Q00D63Q00124Q00343Q00124Q00D79Q003Q00124Q00D83Q000235012Q000F3Q00128F3Q00D93Q000235012Q00103Q00128F3Q00DA3Q000235012Q00113Q00128F3Q00DB3Q000235012Q00123Q00128F3Q00DC3Q000235012Q00133Q00128F3Q00DD3Q000235012Q00143Q00128F3Q00DE3Q000235012Q00153Q00128F3Q00DF3Q000235012Q00163Q00128F3Q00E03Q000235012Q00173Q00128F3Q00E13Q000235012Q00183Q00128F3Q00E23Q000235012Q00193Q00128F3Q00E33Q000235012Q001A3Q00128F3Q00E43Q000235012Q001B3Q00128F3Q00E53Q000235012Q001C3Q00128F3Q00E63Q000235012Q001D3Q00128F3Q00E73Q000235012Q001E3Q00128F3Q00E83Q000235012Q001F3Q00128F3Q00E93Q000235012Q00203Q00128F3Q00EA3Q000235012Q00213Q00128F3Q00EB3Q000235012Q00223Q00128F3Q00EC3Q000235012Q00233Q00128F3Q00ED3Q000235012Q00243Q00128F3Q00EE3Q000235012Q00253Q00128F3Q00EF3Q000235012Q00263Q001246012Q00F03Q00124Q00F23Q00124Q00F19Q003Q00124Q00F39Q003Q00124Q00F43Q00124Q00343Q00124Q00F53Q00124Q00343Q00128F3Q00F63Q0012B83Q00B03Q00124Q00F79Q003Q00124Q00F83Q00124Q00FA3Q00124Q00F99Q003Q00124Q00FB3Q00124Q00FD3Q00124Q00FC3Q00127C012Q00FF3Q00129A012Q00FE3Q00124Q002Q012Q00125Q00012Q00124Q00343Q00124Q0002019Q002Q00124Q0003012Q00124Q00343Q00124Q0004012Q00124Q00343Q00128F3Q0005012Q00124A012Q00253Q00127C2Q01004F4Q000C5Q000100128F3Q0006012Q000235012Q00273Q00128F3Q0007012Q000235012Q00283Q00128F3Q0008013Q0070014Q000800127C2Q01000A012Q001032012Q003D000100127C2Q01000B012Q00127C0102000C013Q0084012Q0001000200127C2Q01000D012Q00127C0102000E013Q0084012Q0001000200127C2Q01000F012Q00127C01020010013Q0084012Q0001000200127C2Q010011012Q00127C01020012013Q0084012Q0001000200127C2Q010013012Q00127C01020014013Q0084012Q0001000200127C2Q010015012Q00127C01020016013Q0084012Q0001000200127C2Q010017012Q00127C01020018013Q0084012Q0001000200128F3Q0009012Q000235012Q00293Q00128F3Q0019012Q000235012Q002A3Q00128F3Q001A013Q00917Q00128F3Q001B012Q000235012Q002B3Q00128F3Q001C012Q000235012Q002C3Q00128F3Q001D012Q000235012Q002D3Q00128F3Q001E012Q000235012Q002E3Q00128F3Q001F012Q000235012Q002F3Q00128F3Q0020012Q000235012Q00303Q00128F3Q0021012Q000235012Q00313Q00128F3Q0022012Q000235012Q00323Q00128F3Q0023012Q000235012Q00333Q00128F3Q0024012Q000235012Q00343Q00128F3Q0025012Q000235012Q00353Q00128F3Q0026012Q000235012Q00363Q00128F3Q0027013Q00917Q00128F3Q0028012Q00124A012Q0029012Q0002352Q0100374Q00E33Q00020001000235012Q00383Q00128F3Q002A012Q000235012Q00393Q00128F3Q002B012Q000235012Q003A3Q00128F3Q002C012Q000235012Q003B3Q00128F3Q002D012Q000235012Q003C3Q00128F3Q002E012Q000235012Q003D3Q00128F3Q002F012Q000235012Q003E3Q00128F3Q0030012Q000235012Q003F3Q00128F3Q0031012Q000235012Q00403Q00128F3Q0032012Q000235012Q00413Q00128F3Q0033012Q000235012Q00423Q00128F3Q0034012Q000235012Q00433Q00128F3Q0035012Q000235012Q00443Q00128F3Q0036012Q000235012Q00453Q00128F3Q0037012Q000235012Q00463Q00128F3Q0038012Q000235012Q00473Q00128F3Q0039012Q000235012Q00483Q00128F3Q003A012Q000235012Q00493Q00128F3Q003B012Q000235012Q004A3Q00128F3Q003C012Q000235012Q004B3Q00128F3Q003D012Q000235012Q004C3Q00128F3Q003E012Q000235012Q004D3Q00128F3Q003F012Q000235012Q004E3Q00128F3Q0040012Q000235012Q004F3Q00128F3Q0041012Q000235012Q00503Q00128F3Q0042012Q000235012Q00513Q00128F3Q0043012Q000235012Q00523Q00128F3Q0044012Q000235012Q00533Q00128F3Q0045012Q000235012Q00543Q00128F3Q0046012Q000235012Q00553Q00128F3Q0047012Q000235012Q00563Q00128F3Q0048012Q000235012Q00573Q00128F3Q0049012Q000235012Q00583Q00128F3Q004A012Q000235012Q00593Q00128F3Q004B012Q000235012Q005A3Q00128F3Q004C012Q000235012Q005B3Q00128F3Q004D012Q000235012Q005C3Q00128F3Q004E012Q000235012Q005D3Q00128F3Q004F012Q000235012Q005E3Q00128F3Q0050012Q000235012Q005F3Q00128F3Q0051012Q000235012Q00603Q00128F3Q0052012Q000235012Q00613Q00128F3Q0053012Q000235012Q00623Q00128F3Q0054012Q000235012Q00633Q00128F3Q0055012Q000235012Q00643Q00128F3Q0056012Q000235012Q00653Q00128F3Q0057012Q000235012Q00663Q00128F3Q0058012Q000235012Q00673Q00128F3Q0059012Q000235012Q00683Q00128F3Q005A012Q000235012Q00693Q00128F3Q005B012Q000235012Q006A3Q00128F3Q005C012Q000235012Q006B3Q00128F3Q005D012Q000235012Q006C3Q00128F3Q005E012Q000235012Q006D3Q00128F3Q005F012Q000235012Q006E3Q0012F83Q0060017Q00053Q00122Q00010062012Q00122Q00020063012Q00122Q00030064012Q00122Q00040065012Q00122Q00050066017Q0005000100128F3Q0061012Q000235012Q006F3Q00128F3Q0067012Q000235012Q00703Q00128F3Q0068012Q000235012Q00713Q00128F3Q0069012Q000235012Q00723Q00128F3Q006A012Q000235012Q00733Q00128F3Q006B012Q000235012Q00743Q00128F3Q006C012Q000235012Q00753Q00128F3Q006D012Q000235012Q00763Q00128F3Q006E012Q000235012Q00773Q00128F3Q006F012Q000235012Q00783Q00128F3Q0070012Q000235012Q00793Q00128F3Q0071012Q000235012Q007A3Q00128F3Q0072012Q000235012Q007B3Q00128F3Q0073012Q000235012Q007C3Q00128F3Q0074012Q000235012Q007D3Q00128F3Q0075012Q000235012Q007E3Q00128F3Q0076012Q000235012Q007F3Q00128F3Q0077012Q000235012Q00803Q00128F3Q0078012Q000235012Q00813Q00128F3Q0079012Q000235012Q00823Q00128F3Q007A012Q000235012Q00833Q00128F3Q007B012Q000235012Q00843Q00128F3Q007C012Q000235012Q00853Q00128F3Q007D012Q000235012Q00863Q00128F3Q007E012Q000235012Q00873Q00128F3Q007F012Q000235012Q00883Q00128F3Q0080012Q000235012Q00893Q00128F3Q0081012Q000235012Q008A3Q00128F3Q0082012Q000235012Q008B3Q00128F3Q0083012Q000235012Q008C3Q00128F3Q0084012Q000235012Q008D3Q00128F3Q0085012Q000235012Q008E3Q00128F3Q0086012Q000235012Q008F3Q00128F3Q0087012Q000235012Q00903Q00128F3Q0088012Q000235012Q00913Q00128F3Q0089012Q000235012Q00923Q00128F3Q008A012Q000235012Q00933Q00128F3Q008B012Q000235012Q00943Q00128F3Q008C012Q000235012Q00953Q00128F3Q008D012Q000235012Q00963Q00128F3Q008E012Q000235012Q00973Q00128F3Q008F012Q000235012Q00983Q00128F3Q0090012Q000235012Q00993Q00128F3Q0091012Q000235012Q009A3Q00128F3Q0092012Q000235012Q009B3Q00128F3Q0093012Q000235012Q009C3Q00128F3Q0094012Q000235012Q009D3Q00128F3Q0095012Q000235012Q009E3Q00128F3Q0096012Q000235012Q009F3Q00128F3Q0097012Q00124A012Q002B3Q00127C2Q010098012Q00124A010200D14Q0084012Q0001000200124A012Q002B3Q00124A2Q010096012Q001032012Q0045000100124A012Q002B3Q00127C2Q010099012Q00124A010200E04Q0084012Q0001000200124A012Q002B3Q00127C2Q01009A012Q00124A010200E24Q0084012Q0001000200124A012Q00443Q00061E012Q000403013Q0004603Q0004030100124A012Q00443Q00124A2Q010096012Q0006A4012Q0004030100010004603Q0004030100124A012Q0029012Q00124A2Q0100444Q00E33Q000200012Q00917Q00128F3Q00443Q000235012Q00A03Q00128F3Q009B012Q00124A012Q002B3Q00127C2Q01009C012Q000235010200A14Q0084012Q0001000200124A012Q002B3Q00127C2Q01009D012Q000235010200A24Q0084012Q0001000200124A012Q002B3Q00127C2Q01009E012Q000235010200A34Q0084012Q0001000200124A012Q002C3Q00124A2Q01002D4Q0079012Q000200020026A03Q001D0301002E0004603Q001D030100124A012Q002D4Q00B53Q000100020006493Q001E030100010004603Q001E030100124A012Q002F3Q00124A2Q01009F012Q001258010200A0015Q00023Q00024Q00010002000200122Q000200A1012Q00062Q00010029030100020004603Q0029030100127C2Q0100A0013Q000A00013Q00010026A00001002A030100230004603Q002A03012Q007100016Q006B2Q0100013Q00061E2Q01003003013Q0004603Q0030030100127C010200A2013Q0091000300034Q0084012Q0002000300127C010200A2013Q000A00023Q0002000649000200C7030100010004603Q00C703012Q0091000200023Q00127C010300A3013Q000A00033Q00030006490003003B030100010004603Q003B030100127C010300A4013Q000A00033Q000300127C010400A5013Q000A00043Q00042Q006B010500013Q0006A401040041030100050004603Q004103012Q007100046Q006B010400013Q00061E2Q01006003013Q0004603Q0060030100124A0105002C3Q00124A010600A6013Q00790105000200020026A0000500600301002E0004603Q0060030100124A0105002C3Q00124A010600A7013Q00790105000200020026A0000500600301002E0004603Q0060030100124A010500A8012Q00127D00060019012Q00122Q000700A9015Q000600076Q00053Q000700044Q005E030100124A010A00A7013Q00F0000B00094Q0079010A0002000200061E010A005E03013Q0004603Q005E030100124A010A00A6013Q00F0000B00094Q0079010A000200022Q00F00002000A3Q0004603Q006003010006A200050054030100020004603Q0054030100064900020086030100010004603Q0086030100061E0103008603013Q0004603Q0086030100124A0105002C3Q0012400006000A3Q00122Q000700AA015Q0006000600074Q00050002000200262Q000500860301002E0004603Q00860301000235010500A43Q00124A01060029012Q000688000700A5000100012Q00F03Q00034Q00B300060002000700061E0106008603013Q0004603Q0086030100124A0108009F013Q00F0000900074Q007901080002000200127C010900A1012Q00069C00080086030100090004603Q008603010026CD00070086030100230004603Q008603012Q00F0000800054Q00F0000900074Q007901080002000200064900080081030100010004603Q008103012Q00F0000200073Q0004603Q0086030100061E0104008603013Q0004603Q0086030100124A010800AB012Q00127C010900AC013Q00E3000800020001000649000200A6030100010004603Q00A60301000649000400A6030100010004603Q00A6030100124A0105002C3Q00124A010600A6013Q00790105000200020026A0000500A60301002E0004603Q00A6030100124A0105002C3Q00124A010600A7013Q00790105000200020026A0000500A60301002E0004603Q00A6030100124A010500A8012Q00127D00060019012Q00122Q000700A9015Q000600076Q00053Q000700044Q00A4030100124A010A00A7013Q00F0000B00094Q0079010A0002000200061E010A00A403013Q0004603Q00A4030100124A010A00A6013Q00F0000B00094Q0079010A000200022Q00F00002000A3Q0004603Q00A603010006A20005009A030100020004603Q009A0301000649000200AB030100010004603Q00AB030100124A010500AB012Q00127C010600AD013Q00E300050002000100124A010500AE013Q00F0000600023Q00127C010700AF013Q00A5010500070006000649000500B8030100010004603Q00B8030100124A010700AB012Q0012DC000800B0012Q00122Q000900B1015Q000A00066Q0009000200024Q0008000800094Q00070002000100124A01070029013Q00F0000800054Q00B3000700020008000649000700C4030100010004603Q00C4030100124A010900AB012Q0012DC000A00B2012Q00122Q000B00B1015Q000C00086Q000B000200024Q000A000A000B4Q00090002000100127C010900A2013Q0084012Q000900082Q002D01025Q00124A012Q002C3Q00124A2Q01002D4Q0079012Q000200020026A03Q00D00301002E0004603Q00D0030100124A012Q002D4Q00B53Q000100020006493Q00D1030100010004603Q00D1030100124A012Q002F3Q00127C2Q0100A2013Q00BF5Q000100124Q00B3019Q000D00122Q000100B5012Q00122Q000200B6017Q0001000200122Q000100B7012Q00122Q000200B6017Q0001000200122Q000100B8012Q00127C010200B9013Q0084012Q0001000200127C2Q0100BA012Q00127C010200BB013Q0084012Q0001000200127C2Q0100BC012Q00127C010200BD013Q0084012Q0001000200127C2Q0100BE012Q00127C010200B24Q0084012Q0001000200127C2Q0100BF012Q00127C010200C0013Q0084012Q0001000200127C2Q0100C1012Q00127C010200C2013Q0084012Q0001000200127C2Q0100C3012Q00127C010200C4013Q0084012Q0001000200127C2Q0100C5012Q00127C010200C6013Q0084012Q0001000200127C2Q0100C7012Q00127C010200C8013Q0084012Q0001000200127C2Q0100C9012Q00127C010200CA013Q0084012Q0001000200127C2Q0100CB012Q00127C0102004F4Q0084012Q0001000200128F3Q00B4012Q000235012Q00A63Q00128F3Q00CC012Q000235012Q00A73Q00128F3Q00CD013Q006B016Q00128F3Q00CE012Q000235012Q00A83Q00128F3Q00CF012Q000235012Q00A93Q00128F3Q00D0012Q00124A012Q002B3Q00127C2Q0100D1012Q000235010200AA4Q0084012Q0001000200124A012Q00293Q00061E012Q001104013Q0004603Q0011040100124A012Q002A3Q0006493Q002F040100010004603Q002F040100124A012Q000A3Q00127C010200D2013Q00D15Q00022Q0079012Q000200020006493Q001D040100010004603Q001D040100124A012Q000A3Q001233000100D3019Q000100122Q000200D4019Q00026Q0002000100124A012Q00093Q00127C2Q0100D5013Q000A5Q00010006493Q0028040100010004603Q0028040100124A012Q00093Q00127C2Q0100D6013Q000A5Q000100127C010200D4013Q00D15Q00022Q0079012Q0002000200128F3Q00293Q00124A012Q00293Q00127C010200D7013Q00D15Q000200127C010200D8013Q00DD3Q0002000200128F3Q002A3Q00124A012Q00D9012Q00127C2Q0100DA013Q00E33Q0002000100124A012Q00DB012Q00127C2Q0100DC013Q000A5Q00010002352Q0100AB4Q00E33Q000200012Q000C012Q00013Q00AC3Q00143Q0003063Q00706C6179657203093Q00706C6179657247756903063Q00506172656E7403043Q0067616D6503083Q0049734C6F6164656403063Q004C6F6164656403043Q005761697403073Q00506C6179657273030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030E3Q0046696E6446697273744368696C6403093Q00506C61796572477569030C3Q0057616974466F724368696C64026Q003E40030E3Q004D6178694875624B65794761746503073Q0044657374726F7903043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C0003053Q007063612Q6C00443Q00124A012Q00013Q00061E012Q000C00013Q0004603Q000C000100124A012Q00023Q00061E012Q000C00013Q0004603Q000C000100124A012Q00023Q002048014Q000300061E012Q000C00013Q0004603Q000C00012Q006B012Q00014Q005C012Q00023Q00124A012Q00043Q002024014Q00052Q0079012Q000200020006493Q0015000100010004603Q0015000100124A012Q00043Q002048014Q0006002024014Q00072Q00E33Q0002000100124A012Q00083Q002048014Q00090006493Q001E000100010004603Q001E000100124A2Q0100083Q0020482Q010001000A0020242Q01000100072Q00792Q01000200022Q00F03Q00013Q00128F3Q00013Q00124A2Q0100013Q0020242Q010001000B00127C0103000C4Q00DD00010003000200128F000100023Q00124A2Q0100023Q0006490001002D000100010004603Q002D000100124A2Q0100013Q0020242Q010001000D00127C0103000C3Q00127C0104000E4Q00DD00010004000200128F000100023Q00124A2Q0100023Q00064900010032000100010004603Q003200012Q006B2Q016Q005C2Q0100023Q00124A2Q0100023Q0020242Q010001000B00127C0103000F4Q00DD00010003000200061E2Q01003A00013Q0004603Q003A00010020240102000100102Q00E300020002000100124A010200113Q0020480102000200120026A000020041000100130004603Q0041000100124A010200143Q00023501036Q00E30002000200012Q006B010200014Q005C010200024Q000C012Q00013Q00013Q00043Q0003043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646500053Q001263012Q00013Q00122Q000100033Q00202Q00010001000400104Q000200016Q00017Q00033Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964030E3Q006661726D436865636B5061757365010D3Q00124A2Q0100013Q00061E2Q01000B00013Q0004603Q000B000100124A2Q0100023Q00069C3Q0009000100010004603Q0009000100124A2Q0100034Q00C4000100013Q0004603Q000B00012Q007100016Q006B2Q0100014Q005C2Q0100024Q000C012Q00017Q00083Q0003063Q00747970656F6603063Q00737472696E6703053Q006C6F77657203043Q0066696E6403063Q0063616E63656C026Q00F03F0003073Q0063616E63652Q6C01213Q00124A2Q0100014Q00F000026Q00792Q01000200020026CD00010007000100020004603Q000700012Q006B2Q016Q005C2Q0100023Q00124A2Q0100023Q0020672Q01000100034Q00028Q00010002000200122Q000200023Q00202Q0002000200044Q000300013Q00122Q000400053Q00122Q000500066Q000600016Q00020006000200262Q0002001E000100070004603Q001E000100124A010200023Q0020510002000200044Q000300013Q00122Q000400083Q00122Q000500066Q000600016Q00020006000200262Q0002001E000100070004603Q001E00012Q007100026Q006B010200014Q005C010200024Q000C012Q00017Q00013Q0003053Q007063612Q6C00043Q00124A012Q00013Q0002352Q016Q00E33Q000200012Q000C012Q00013Q00013Q00043Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q00456E756D03093Q00496E7669736963616D00063Q00121A012Q00013Q00122Q000100033Q00202Q00010001000200202Q00010001000400104Q000200016Q00017Q00023Q0003103Q0063616D657261436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400093Q00124A012Q00013Q00061E012Q000800013Q0004603Q0008000100124A012Q00013Q002024014Q00022Q00E33Q000200012Q00917Q00128F3Q00014Q000C012Q00017Q00023Q00030E3Q0073746F7043616D6572614C2Q6F7003053Q007063612Q6C00063Q00124A012Q00014Q0028012Q0001000100124A012Q00023Q0002352Q016Q00E33Q000200012Q000C012Q00013Q00013Q00063Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03043Q00456E756D03043Q005A2Q6F6D000A3Q00124A012Q00013Q00124A2Q0100033Q0020482Q010001000400064900010008000100010004603Q0008000100124A2Q0100053Q0020482Q01000100020020482Q0100010006001032012Q000200012Q000C012Q00017Q00063Q00030E3Q0073746F7043616D6572614C2Q6F70030E3Q00612Q706C79496E7669736963616D03103Q0063616D657261436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374000B3Q00127E3Q00018Q0001000100124Q00028Q0001000100124Q00043Q00206Q0005002024014Q000600124A010200024Q00DD3Q0002000200128F3Q00034Q000C012Q00017Q00203Q00030E3Q00626C61636B5363722Q656E47756903063Q00506172656E7403093Q00706C6179657247756903083Q00496E7374616E63652Q033Q006E657703093Q005363722Q656E47756903043Q004E616D6503123Q004D617869487562426C61636B5363722Q656E030C3Q00536574412Q74726962757465030C3Q0052657365744F6E537061776E0100030E3Q0049676E6F7265477569496E7365742Q01030E3Q005A496E6465784265686176696F7203043Q00456E756D03073Q005369626C696E67030C3Q00446973706C61794F72646572024Q007C842E4103073Q00456E61626C656403053Q004672616D6503073Q004F7665726C617903043Q0053697A6503053Q005544696D3203093Q0066726F6D5363616C65026Q00F03F03083Q00506F736974696F6E028Q0003103Q004261636B67726F756E64436F6C6F723303063Q00436F6C6F723303163Q004261636B67726F756E645472616E73706172656E6379030F3Q00426F7264657253697A65506978656C03063Q005A496E646578003D3Q00124A012Q00013Q00061E012Q000800013Q0004603Q0008000100124A012Q00013Q002048014Q000200061E012Q000800013Q0004603Q000800012Q000C012Q00013Q00124A012Q00033Q0006493Q000C000100010004603Q000C00012Q000C012Q00013Q00124A012Q00043Q0020F25Q000500122Q000100068Q0002000200304Q0007000800202Q00013Q000900122Q000300086Q000400016Q00010004000100304Q000A000B00304Q000C000D00124A2Q01000F3Q00202700010001000E00202Q00010001001000104Q000E000100304Q0011001200304Q0013000B00122Q000100033Q00104Q0002000100122Q000100043Q00202Q00010001000500122Q000200144Q00792Q010002000200300E2Q010007001500122Q000200173Q00202Q00020002001800122Q000300193Q00122Q000400196Q00020004000200102Q00010016000200122Q000200173Q00202Q00020002001800122Q0003001B3Q00127C0104001B4Q00DD0002000400020010322Q01001A000200124A0102001D3Q00206300020002000500122Q0003001B3Q00122Q0004001B3Q00122Q0005001B6Q0002000500020010322Q01001C000200309F2Q01001E001B00309F2Q01001F001B00309F2Q01002000190010322Q0100023Q00128F3Q00014Q000C012Q00017Q000E3Q0003103Q0052656E646572336444697361626C656403123Q00426C61636B5363722Q656E4F7665726C617903143Q00656E73757265426C61636B5363722Q656E477569030E3Q00626C61636B5363722Q656E47756903073Q00456E61626C65643Q010003063Q0069706169727303093Q00706C61796572477569030B3Q004765744368696C6472656E2Q033Q0049734103093Q005363722Q656E477569030C3Q00476574412Q7472696275746503123Q004D617869487562426C61636B5363722Q656E002D3Q00124A012Q00013Q00061E012Q000400013Q0004603Q0004000100124A012Q00023Q00061E012Q000E00013Q0004603Q000E000100124A2Q0100034Q00282Q010001000100124A2Q0100043Q00061E2Q01002C00013Q0004603Q002C000100124A2Q0100043Q00309F2Q01000500060004603Q002C000100124A2Q0100043Q00061E2Q01001300013Q0004603Q0013000100124A2Q0100043Q00309F2Q010005000700124A2Q0100083Q00124A010200093Q00061E0102001C00013Q0004603Q001C000100124A010200093Q00202401020002000A2Q00790102000200020006490002001D000100010004603Q001D00012Q007001026Q00B30001000200030004603Q002A000100202401060005000B00127C0108000C4Q00DD00060008000200061E0106002A00013Q0004603Q002A000100202401060005000D00127C0108000E4Q00DD0006000800020026A00006002A000100060004603Q002A000100309F0105000500070006A20001001F000100020004603Q001F00012Q000C012Q00017Q000B3Q0003103Q0052656E646572336444697361626C65642Q0103023Q005F4703083Q00726E64725F64697303043Q0067656E7603053Q007063612Q6C03183Q00757064617465426C61636B5363722Q656E4F7665726C617903113Q0073657452656E6465723364546F2Q676C6503143Q0072656E6465723364546F2Q676C6553696C656E7403083Q00736B69705361766503123Q007363686564756C6553617665436F6E66696702253Q00064900010004000100010004603Q000400012Q007001026Q00F0000100023Q0026CD3Q0007000100020004603Q000700012Q007100026Q006B010200013Q001274000200013Q00122Q000200033Q00122Q000300013Q00102Q00020004000300122Q000200053Q00122Q000300013Q00102Q00020004000300122Q000200063Q00023501036Q00E200020002000100122Q000200076Q00020001000100122Q000200083Q00062Q0002001F00013Q0004603Q001F00012Q006B010200013Q00128F000200093Q00124A010200083Q00124A010300014Q006B010400014Q00680102000400012Q006B01025Q00128F000200093Q00204801020001000A00064900020024000100010004603Q0024000100124A0102000B4Q00280102000100012Q000C012Q00013Q00013Q00033Q00030A3Q0052756E5365727669636503153Q00536574336452656E646572696E67456E61626C656403103Q0052656E646572336444697361626C656400063Q00124A012Q00013Q002024014Q000200124A010200034Q00C4000200024Q0068012Q000200012Q000C012Q00017Q00023Q0003123Q00612Q706C7952656E6465723364537461746503103Q0052656E646572336444697361626C656400053Q0012F43Q00013Q00122Q000100026Q000100018Q000200016Q00017Q00083Q0003123Q004175746F52656E64657233644F6E4661726D03123Q0072656E64657233644661726D41637469766503183Q0072656E64657233644661726D4E2Q656473526573746F726503103Q0052656E646572336444697361626C656403123Q00612Q706C7952656E6465723364537461746503063Q0073696C656E742Q0103083Q00736B69705361766500133Q00124A012Q00013Q00061E012Q000600013Q0004603Q0006000100124A012Q00023Q00061E012Q000700013Q0004603Q000700012Q000C012Q00014Q006B012Q00013Q00128F3Q00023Q00124A012Q00044Q00C47Q00128F3Q00033Q00124A012Q00054Q006B2Q0100014Q007001023Q000200309F01020006000700309F0102000800072Q0068012Q000200012Q000C012Q00017Q000F3Q0003123Q0072656E64657233644661726D41637469766503183Q0072656E64657233644661726D4E2Q656473526573746F726503123Q0072656E64657233644265666F72654661726D03123Q00612Q706C7952656E6465723364537461746503063Q0073696C656E742Q0103083Q00736B69705361766503053Q007063612Q6C03103Q0052656E646572336444697361626C656403023Q005F4703083Q00726E64725F64697303043Q0067656E7603183Q00757064617465426C61636B5363722Q656E4F7665726C617903113Q0073657452656E6465723364546F2Q676C6503143Q0072656E6465723364546F2Q676C6553696C656E74002B3Q00124A012Q00013Q0006493Q0004000100010004603Q000400012Q000C012Q00014Q006B016Q001288012Q00013Q00124Q00026Q00015Q00122Q000100026Q000100013Q00122Q000100033Q00064Q001400013Q0004603Q0014000100124A2Q0100044Q006B01026Q007001033Q000200309F01030005000600309F0103000700062Q00682Q01000300010004603Q002A000100124A2Q0100083Q00023501026Q009F0001000200014Q000100013Q00122Q000100093Q00122Q0001000A3Q00302Q0001000B000600122Q0001000C3Q00302Q0001000B000600122Q0001000D6Q00010001000100122Q0001000E3Q00062Q0001002A00013Q0004603Q002A00012Q006B2Q0100013Q0012E50001000F3Q00122Q0001000E6Q000200016Q000300016Q0001000300014Q00015Q00122Q0001000F4Q000C012Q00013Q00013Q00023Q00030A3Q0052756E5365727669636503153Q00536574336452656E646572696E67456E61626C656400053Q001276012Q00013Q00206Q00024Q00029Q00000200016Q00017Q00093Q0003123Q0072656E64657233644265666F72654661726D03123Q0072656E64657233644661726D41637469766503183Q0072656E64657233644661726D4E2Q656473526573746F726503053Q007063612Q6C03023Q005F4703083Q00726E64725F646973010003043Q0067656E76030E3Q00626C61636B5363722Q656E47756900153Q0012D73Q00019Q003Q00124Q00029Q003Q00124Q00033Q00124Q00043Q0002352Q016Q008D3Q0002000100124Q00053Q00304Q0006000700124Q00083Q00304Q0006000700124Q00093Q00064Q001400013Q0004603Q0014000100124A012Q00043Q0002352Q0100014Q00E33Q000200012Q00917Q00128F3Q00094Q000C012Q00013Q00023Q00023Q00030A3Q0052756E5365727669636503153Q00536574336452656E646572696E67456E61626C656400053Q001276012Q00013Q00206Q00024Q000200018Q000200016Q00017Q00023Q00030E3Q00626C61636B5363722Q656E47756903073Q0044657374726F7900043Q00124A012Q00013Q002024014Q00022Q00E33Q000200012Q000C012Q00017Q00053Q0003063Q00747970656F6603093Q00777269746566696C6503083Q0066756E6374696F6E03083Q007265616466696C6503063Q00697366696C6500133Q00124A012Q00013Q00124A2Q0100024Q0079012Q000200020026A03Q000F000100030004603Q000F000100124A012Q00013Q00124A2Q0100044Q0079012Q000200020026A03Q000F000100030004603Q000F000100124A012Q00013Q00124A2Q0100054Q0079012Q000200020026CD3Q0010000100030004603Q001000012Q00718Q006B012Q00014Q005C012Q00024Q000C012Q00017Q00063Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030B3Q00434F4E4649475F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C6500193Q00124A012Q00014Q00B53Q0001000200061E012Q000900013Q0004603Q0009000100124A012Q00023Q00124A2Q0100034Q0079012Q000200020006493Q000B000100010004603Q000B00012Q0070017Q005C012Q00023Q00124A012Q00043Q0002352Q016Q00B33Q0002000100061E012Q001600013Q0004603Q0016000100124A010200054Q00F0000300014Q00790102000200020026A000020016000100060004603Q001600012Q005C2Q0100024Q007001026Q005C010200024Q000C012Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030B3Q00434F4E4649475F46494C4500083Q0012FB3Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00063Q0003103Q0063616E557365436F6E66696746696C6503063Q00747970656F6603053Q007461626C6503053Q007063612Q6C03043Q007761726E031D3Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B0204A534F4E3A011F3Q00124A2Q0100014Q00B500010001000200061E2Q01000900013Q0004603Q0009000100124A2Q0100024Q00F000026Q00792Q01000200020026CD0001000B000100030004603Q000B00012Q006B2Q016Q005C2Q0100023Q00124A2Q0100043Q00068800023Q000100012Q00F08Q00B300010002000200064900010017000100010004603Q0017000100124A010300053Q001280000400066Q000500026Q0003000500014Q00038Q000300024Q006B01035Q00124A010400043Q00068800050001000100022Q00F03Q00024Q00F03Q00034Q00E30004000200012Q005C010300024Q000C012Q00013Q00023Q00023Q00030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500063Q001299012Q00013Q00206Q00024Q00029Q0000029Q008Q00017Q00023Q0003093Q00777269746566696C65030B3Q00434F4E4649475F46494C4500073Q001250012Q00013Q00122Q000100026Q00029Q00000200016Q00018Q00018Q00017Q000C3Q0003043Q007479706503053Q007461626C6503053Q00706169727303063Q00737472696E67026Q00084003043Q006D61746803053Q00636C616D7003053Q00666C2Q6F72026Q00F03F028Q00025Q00E06F40027Q004001443Q00124A2Q0100014Q00F000026Q00792Q01000200020026CD00010007000100020004603Q000700012Q0091000100014Q005C2Q0100024Q00702Q015Q00124A010200034Q00F000036Q00B30002000200040004603Q0040000100124A010700014Q00F0000800054Q00790107000200020026A000070040000100040004603Q0040000100124A010700014Q00F0000800064Q00790107000200020026A000070040000100020004603Q004000012Q0019000700063Q000E6700050040000100070004603Q004000012Q0070010700023Q00124A010800063Q00207401080008000700122Q000900063Q00202Q00090009000800202Q000A0006000900062Q000A0022000100010004603Q0022000100127C010A000A4Q007901090002000200129B000A000A3Q00122Q000B000B6Q0008000B000200122Q000900063Q00202Q00090009000700122Q000A00063Q00202Q000A000A000800202Q000B0006000C00062Q000B002E000100010004603Q002E000100127C010B000A4Q0079010A0002000200129B000B000A3Q00122Q000C000B6Q0009000C000200122Q000A00063Q00202Q000A000A000700122Q000B00063Q00202Q000B000B000800202Q000C0006000500062Q000C003A000100010004603Q003A000100127C010C000A4Q0079010B0002000200127C010C000A3Q00127C010D000B4Q003F000A000D4Q007701073Q00012Q00842Q01000500070006A20002000C000100020004603Q000C00012Q005C2Q0100024Q000C012Q00017Q00193Q0003043Q007479706503103Q00426C6F636B65645A6F6E65734C69737403053Q007461626C6503063Q0069706169727303063Q0063656E746572026Q00084003063Q00696E7365727403043Q006E616D6503063Q00737472696E6703013Q004C03113Q007A6F6E655F64656661756C745F6E616D6503013Q002003083Q00746F6E756D626572026Q00F03F028Q00027Q004003043Q0073697A6503043Q006D61746803053Q00636C616D7003053Q00666C2Q6F7203113Q0044454641554C545F5A4F4E455F53495A45026Q003440026Q005E4003073Q00656E61626C6564012Q005C4Q00BD7Q00122Q000100013Q00122Q000200026Q00010002000200262Q00010007000100030004603Q000700012Q005C012Q00023Q00124A2Q0100043Q00124A010200024Q00B30001000200030004603Q0058000100124A010600014Q00F0000700054Q00790106000200020026A000060058000100030004603Q0058000100124A010600013Q0020480107000500052Q00790106000200020026A000060058000100030004603Q005800010020480106000500052Q0019000600063Q000E6700060058000100060004603Q0058000100124A010600033Q0020290106000600074Q00078Q00083Q000400122Q000900013Q00202Q000A000500084Q00090002000200262Q00090025000100090004603Q002500010020480109000500080006490009002B000100010004603Q002B000100124A0109000A3Q00127C010A000B4Q007901090002000200127C010A000C4Q00F0000B00044Q000B01090009000B0010320108000800092Q0077000900033Q00122Q000A000D3Q00202Q000B0005000500202Q000B000B000E4Q000A0002000200062Q000A0034000100010004603Q0034000100127C010A000F3Q00124A010B000D3Q002048010C00050005002048010C000C00102Q0079010B00020002000649000B003B000100010004603Q003B000100127C010B000F3Q00124A010C000D3Q002048010D00050005002048010D000D00062Q0079010C00020002000649000C0042000100010004603Q0042000100127C010C000F4Q003601090003000100103201080005000900124A010900123Q00207401090009001300122Q000A00123Q00202Q000A000A001400202Q000B0005001100062Q000B004C000100010004603Q004C000100124A010B00154Q0079010A00020002001228000B00163Q00122Q000C00176Q0009000C000200102Q00080011000900202Q00090005001800262Q00090055000100190004603Q005500012Q007100096Q006B010900013Q0010320108001800092Q00680106000800010006A20001000B000100020004603Q000B00012Q005C012Q00024Q000C012Q00017Q00163Q0003043Q007479706503053Q007461626C6503063Q0069706169727303063Q0063656E746572026Q00084003063Q00696E7365727403043Q006E616D6503063Q00737472696E67034Q0003083Q00746F6E756D626572026Q00F03F028Q00027Q004003043Q0073697A6503043Q006D61746803053Q00636C616D7003053Q00666C2Q6F7203113Q0044454641554C545F5A4F4E455F53495A45026Q003440026Q005E4003073Q00656E61626C6564010001574Q000800015Q00122Q000200016Q00038Q00020002000200262Q00020007000100020004603Q000700012Q005C2Q0100023Q00124A010200034Q00F000036Q00B30002000200040004603Q0053000100124A010700014Q00F0000800064Q00790107000200020026A000070053000100020004603Q0053000100124A010700013Q0020480108000600042Q00790107000200020026A000070053000100020004603Q005300010020480107000600042Q0019000700073Q000E6700050053000100070004603Q0053000100124A010700023Q0020290107000700064Q000800016Q00093Q000400122Q000A00013Q00202Q000B000600074Q000A0002000200262Q000A0025000100080004603Q00250001002048010A00060007000649000A0026000100010004603Q0026000100127C010A00093Q00103201090007000A2Q0077000A00033Q00122Q000B000A3Q00202Q000C0006000400202Q000C000C000B4Q000B0002000200062Q000B002F000100010004603Q002F000100127C010B000C3Q00124A010C000A3Q002048010D00060004002048010D000D000D2Q0079010C00020002000649000C0036000100010004603Q0036000100127C010C000C3Q00124A010D000A3Q002048010E00060004002048010E000E00052Q0079010D00020002000649000D003D000100010004603Q003D000100127C010D000C4Q0036010A0003000100103201090004000A00124A010A000F3Q002074010A000A001000122Q000B000F3Q00202Q000B000B001100202Q000C0006000E00062Q000C0047000100010004603Q0047000100124A010C00124Q0079010B00020002001228000C00133Q00122Q000D00146Q000A000D000200102Q0009000E000A00202Q000A0006001500262Q000A0050000100160004603Q005000012Q0071000A6Q006B010A00013Q00103201090015000A2Q00680107000900010006A20002000B000100020004603Q000B00012Q005C2Q0100024Q000C012Q00017Q003C3Q00030D3Q00436F6E66696756657273696F6E030E3Q00434F4E4649475F56455253494F4E030E3Q0054656C65706F727448656967687403133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B03113Q004C656769744D6F75736543617074757265030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203103Q004661726D54722Q6573456E61626C656403113Q004661726D53746F6E6573456E61626C6564030E3Q005461726765745069636B4D6F6465030C3Q0054656C65706F72744D6F646503103Q0054656C65706F72745374657053697A6503113Q0054656C65706F72745374657044656C6179030B3Q00412Q7461636B44656C617903103Q00426C6F636B65645A6F6E65734C69737403193Q0073657269616C697A65426C6F636B65645A6F6E65734C697374030A3Q00457370456E61626C656403083Q0045737054722Q657303093Q0045737053746F6E6573030A3Q00457370506C6179657273030C3Q004573705265736F7572636573030A3Q00457370447261676F6E73030A3Q004573705472616365727303083Q004573704E616D6573030B3Q004573705465787453697A6503093Q00457370436F6C6F727303123Q0073657269616C697A65457370436F6C6F727303113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B54726164657303103Q0052656E646572336444697361626C656403123Q004175746F52656E64657233644F6E4661726D03123Q00426C61636B5363722Q656E4F7665726C6179030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A65030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F70030A3Q0055694C616E6775616765030C3Q006D61696E4672616D6552656603063Q00506172656E7403083Q00506F736974696F6E03083Q005569585363616C6503013Q005803053Q005363616C6503093Q005569584F2Q6673657403063Q004F2Q6673657403083Q005569595363616C6503013Q005903093Q005569594F2Q6673657400774Q00AF5Q001C00122Q000100023Q00104Q0001000100122Q000100033Q00104Q0003000100122Q000100043Q00104Q0004000100122Q000100053Q00104Q0005000100122Q000100063Q00104Q0006000100122Q000100073Q00104Q0007000100122Q000100083Q00104Q0008000100122Q000100093Q00104Q0009000100122Q0001000A3Q00104Q000A000100122Q0001000B3Q00104Q000B000100122Q0001000C3Q00104Q000C000100122Q0001000D3Q00104Q000D000100122Q0001000E3Q00104Q000E000100122Q0001000F3Q00104Q000F000100122Q000100103Q00104Q0010000100122Q000100113Q00104Q0011000100122Q000100123Q00104Q0012000100122Q000100146Q00010001000200104Q0013000100122Q000100153Q00104Q0015000100122Q000100163Q00104Q0016000100122Q000100173Q00104Q0017000100122Q000100183Q00104Q0018000100122Q000100193Q00104Q0019000100122Q0001001A3Q00104Q001A000100122Q0001001B3Q00104Q001B000100122Q0001001C3Q00104Q001C000100122Q0001001D3Q00104Q001D000100122Q0001001F3Q00122Q0002001E6Q00010002000200104Q001E000100122Q000100203Q00104Q0020000100122Q000100213Q00104Q0021000100122Q000100223Q00104Q0022000100122Q000100233Q00104Q0023000100122Q000100243Q00104Q0024000100122Q000100253Q00104Q0025000100122Q000100263Q00104Q0026000100122Q000100273Q00104Q0027000100122Q000100283Q00104Q0028000100122Q000100293Q00104Q0029000100124A2Q01002A3Q0010D03Q002A000100122Q0001002B3Q00104Q002B000100122Q0001002C3Q00104Q002C000100122Q0001002D3Q00104Q002D000100122Q0001002E3Q00104Q002E000100122Q0001002F3Q00104Q002F000100122Q000100303Q00104Q0030000100122Q000100313Q00104Q0031000100122Q000100323Q00062Q0001007500013Q0004603Q0075000100124A2Q0100323Q0020482Q010001003300061E2Q01007500013Q0004603Q0075000100124A2Q0100323Q0020FC00010001003400202Q00020001003600202Q00020002003700104Q0035000200202Q00020001003600202Q00020002003900104Q0038000200202Q00020001003B00202Q00020002003700104Q003A000200202Q00020001003B00202Q00020002003900104Q003C00022Q005C012Q00024Q000C012Q00017Q00053Q0003103Q0063616E557365436F6E66696746696C6503123Q006275696C64436F6E6669675061796C6F6164030F3Q0072656164436F6E6669675461626C6503053Q00706169727303103Q007772697465436F6E6669675461626C6500143Q00124A012Q00014Q00B53Q000100020006493Q0005000100010004603Q000500012Q000C012Q00013Q00124A012Q00024Q00B53Q0001000200124A2Q0100034Q005B00010001000200122Q000200046Q00038Q00020002000400044Q000E00012Q00842Q01000500060006A20002000D000100020004603Q000D000100124A010200054Q00F0000300014Q00E30002000200012Q000C012Q00017Q00063Q0003103Q0063616E557365436F6E66696746696C6503063Q00747970656F6603053Q007461626C65030F3Q0072656164436F6E6669675461626C6503053Q00706169727303103Q007772697465436F6E6669675461626C6501173Q00124A2Q0100014Q00B500010001000200061E2Q01000900013Q0004603Q0009000100124A2Q0100024Q00F000026Q00792Q01000200020026CD0001000A000100030004603Q000A00012Q000C012Q00013Q00124A2Q0100044Q005B00010001000200122Q000200056Q00038Q00020002000400044Q001100012Q00842Q01000500060006A200020010000100020004603Q0010000100124A010200064Q00F0000300014Q00E30002000200012Q000C012Q00017Q00063Q00030F3Q0073617665436F6E666967546F6B656E026Q00F03F03133Q0073617665436F6E6669675363686564756C656403043Q007461736B03053Q0064656C6179026Q00D03F00113Q001297012Q00013Q00206Q000200124Q00013Q00124Q00013Q00122Q000100033Q00062Q0001000800013Q0004603Q000800012Q000C012Q00014Q006B2Q0100013Q00128F000100033Q00124A2Q0100043Q0020482Q010001000500127C010200063Q00068800033Q000100012Q00F08Q00682Q01000300012Q000C012Q00013Q00013Q00043Q00030F3Q0073617665436F6E666967546F6B656E03133Q0073617665436F6E6669675363686564756C656403123Q007363686564756C6553617665436F6E666967030A3Q0073617665436F6E666967000E4Q0096016Q00124A2Q0100013Q0006A4012Q0009000100010004603Q000900012Q006B016Q00128F3Q00023Q00124A012Q00034Q0028012Q000100012Q000C012Q00014Q006B016Q00128F3Q00023Q00124A012Q00044Q0028012Q000100012Q000C012Q00017Q00043Q00030F3Q0073617665436F6E666967546F6B656E026Q00F03F03133Q0073617665436F6E6669675363686564756C6564030A3Q0073617665436F6E66696700083Q00124A012Q00013Q0020655Q000200128F3Q00014Q006B016Q00128F3Q00033Q00124A012Q00044Q0028012Q000100012Q000C012Q00017Q00073Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C65030B3Q0070656E64696E6753652Q6C001C3Q00124A012Q00014Q00B53Q0001000200061E012Q000900013Q0004603Q0009000100124A012Q00023Q00124A2Q0100034Q0079012Q000200020006493Q000B000100010004603Q000B00012Q00918Q005C012Q00023Q00124A012Q00043Q0002352Q016Q00B33Q0002000100061E012Q001900013Q0004603Q0019000100124A010200054Q00F0000300014Q00790102000200020026A000020019000100060004603Q0019000100204801020001000700061E0102001900013Q0004603Q001900012Q005C2Q0100024Q0091000200024Q005C010200024Q000C012Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030F3Q0053452Q4C5F53544154455F46494C4500083Q0012FB3Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00023Q00030D3Q006C6F616453652Q6C53746174652Q00083Q00124A012Q00014Q00B53Q000100020026A03Q0005000100020004603Q000500012Q00718Q006B012Q00014Q005C012Q00024Q000C012Q00017Q00093Q0003103Q0063616E557365436F6E66696746696C65030B3Q0070656E64696E6753652Q6C2Q0103053Q00706861736503063Q006D616E75616C030A3Q00726573756D654661726D03073Q007361766564417403043Q007469636B03053Q007063612Q6C02203Q00064900010004000100010004603Q000400012Q007001026Q00F0000100023Q00124A010200014Q00B500020001000200064900020009000100010004603Q000900012Q000C012Q00014Q007001023Q000500309F010200020003001032010200043Q0020480103000100050026CD00030010000100030004603Q001000012Q007100036Q006B010300013Q0010320102000500030020480103000100060026CD00030016000100030004603Q001600012Q007100036Q006B010300013Q00109400020006000300122Q000300086Q00030001000200102Q00020007000300122Q000300093Q00068800043Q000100012Q00F03Q00024Q00E30003000200012Q000C012Q00013Q00013Q00043Q0003093Q00777269746566696C65030F3Q0053452Q4C5F53544154455F46494C45030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500083Q00120A012Q00013Q00122Q000100023Q00122Q000200033Q00202Q0002000200044Q00048Q000200049Q0000016Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503053Q007063612Q6C00093Q00124A012Q00014Q00B53Q000100020006493Q0005000100010004603Q000500012Q000C012Q00013Q00124A012Q00023Q0002352Q016Q00E33Q000200012Q000C012Q00013Q00013Q00073Q0003063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503093Q00777269746566696C65030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465030B3Q0070656E64696E6753652Q6C012Q000E3Q00124A012Q00013Q00124A2Q0100024Q0079012Q0002000200061E012Q000D00013Q0004603Q000D000100124A012Q00033Q0012A12Q0100023Q00122Q000200043Q00202Q0002000200054Q00043Q000100302Q0004000600074Q000200049Q0000012Q000C012Q00017Q00013Q0003053Q007063612Q6C01093Q0006493Q0004000100010004603Q000400012Q00702Q016Q00F03Q00013Q00124A2Q0100013Q00068800023Q000100012Q00F08Q00E30001000200012Q000C012Q00013Q00013Q00083Q0003053Q00666F72636503153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003153Q006C6F674661726D53652Q73696F6E446973636F726403213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B0023Q00E081386E4103103Q00446973636F72644C6F674F6E53652Q6C00184Q0096016Q002048014Q000100061E012Q001000013Q0004603Q0010000100124A012Q00023Q00061E012Q001700013Q0004603Q0017000100124A012Q00034Q00B53Q000100020026CD3Q0017000100040004603Q0017000100124A012Q00053Q00127C2Q0100063Q00127C010200074Q0068012Q000200010004603Q0017000100124A012Q00083Q00061E012Q001700013Q0004603Q0017000100124A012Q00053Q00127C2Q0100063Q00127C010200074Q0068012Q000200012Q000C012Q00017Q00053Q00030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F67030A3Q00726573756D654661726D03043Q007461736B03053Q006465666572020E3Q001283010200016Q00020001000100122Q000200026Q00038Q00020002000100202Q00023Q000300062Q0002000C00013Q0004603Q000C000100124A010200043Q00204801020002000500023501036Q00E30002000200012Q005C2Q0100024Q000C012Q00013Q00013Q00043Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D00113Q00124A012Q00013Q0006493Q0010000100010004603Q001000012Q006B012Q00013Q00128F3Q00023Q00124A012Q00033Q00061E012Q000C00013Q0004603Q000C000100124A012Q00034Q006B2Q0100014Q006B010200014Q0068012Q000200012Q006B016Q00128F3Q00023Q00124A012Q00044Q0028012Q000100012Q000C012Q00017Q00063Q0003063Q00697061697273030A3Q0053452Q4C5F4954454D5303103Q0073652Q6C5265736F757263654974656D029A5Q99B93F03043Q007461736B03043Q0077616974022B4Q00DE00025Q00122Q000300013Q00122Q000400026Q00030002000500044Q0027000100061E2Q01000C00013Q0004603Q000C00012Q00F0000800014Q00B50008000100020006490008000C000100010004603Q000C00010004603Q0029000100124A010800034Q00F0000900074Q007901080002000200061E0108001200013Q0004603Q001200012Q006B010200013Q00124A010800024Q0019000800083Q0006170106001F000100080004603Q001F000100061E012Q001F00013Q0004603Q001F00012Q00F000085Q00127C010900044Q007901080002000200064900080027000100010004603Q002700010004603Q002900010004603Q0027000100124A010800024Q0019000800083Q00061701060027000100080004603Q0027000100124A010800053Q00204801080008000600127C010900044Q00E30008000200010006A200030005000100020004603Q000500012Q005C010200024Q000C012Q00017Q00033Q00030D3Q006C6F616453652Q6C537461746503043Q007461736B03053Q00737061776E000E3Q00124A012Q00014Q00B53Q000100020006493Q0006000100010004603Q000600012Q006B2Q016Q005C2Q0100023Q00124A2Q0100023Q0020482Q010001000300068800023Q000100012Q00F08Q00E30001000200012Q006B2Q0100014Q005C2Q0100024Q000C012Q00013Q00013Q001D3Q00030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0073652Q6C03053Q00666F72636503063Q006D616E75616C2Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303053Q007068617365032A3Q00D092D0BED0B7D0BED0B1D0BDD0BED0B2D0BBD18FD0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E03133Q0077616974466F72436861726163746572487270026Q00284003043Q007461736B03043Q007761697403123Q0053452Q4C5F574149545F41465445525F545003203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D73030D3Q007361766553652Q6C537461746503063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q00776F726C6454656C65706F7274030D3Q004641524D5F574F524C445F4944027Q0040030D3Q006C6F616453652Q6C537461746503123Q0066696E616C697A6553652Q6C526573756D6503243Q00D097D0B0D0B2D0B5D180D188D0B0D0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E026Q00F03F030E3Q00636C65617253652Q6C537461746503043Q0069646C6500673Q00124A012Q00013Q00061E012Q000400013Q0004603Q000400012Q000C012Q00014Q006B012Q00013Q0012343Q00013Q00124Q00033Q00124Q00029Q0000034Q00015Q00202Q00010001000500262Q0001000E000100060004603Q000E00012Q007100016Q006B2Q0100013Q001032012Q000400012Q00962Q015Q0020482Q01000100070026CD00010015000100060004603Q001500012Q007100016Q006B2Q0100013Q001032012Q000700010002352Q015Q001032012Q0008000100068800010001000100012Q00F08Q009601025Q0020480102000200090026A00002004D000100030004603Q004D00012Q00F0000200013Q00120F0003000A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q00020002000100126A0102000D3Q00202Q00020002000E00122Q0003000F6Q0002000200014Q000200013Q00122Q000300106Q00020002000100122Q000200113Q000235010300023Q000235010400034Q004300020004000200122Q000300123Q00122Q000400136Q00058Q0003000500014Q000300013Q00122Q000400146Q00030002000100122Q000300153Q00122Q000400164Q00E300030002000100124A0103000B3Q00127C0104000C4Q00E300030002000100124A0103000D3Q00204801030003000E00127C010400174Q00E300030002000100124A010300184Q00B500030001000200061E0103006200013Q0004603Q006200010020480104000300090026A000040062000100130004603Q0062000100124A010400194Q00F000056Q00F0000600024Q00680104000600010004603Q006200012Q009601025Q0020480102000200090026A000020060000100130004603Q006000012Q00F0000200013Q00120F0003001A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q00020002000100124A0102000D3Q00204801020002000E00127C0103001B4Q00E300020002000100124A010200194Q00F000036Q006B010400014Q00680102000400010004603Q0062000100124A0102001C4Q00280102000100012Q006B01025Q00128F000200013Q00127C0102001D3Q00128F000200024Q000C012Q00013Q00043Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q00124A2Q0100013Q00061E2Q01000900013Q0004603Q0009000100124A2Q0100013Q0020482Q010001000200061E2Q01000900013Q0004603Q0009000100124A2Q0100013Q0010322Q0100034Q000C012Q00017Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q00962Q015Q0020482Q010001000100061E2Q01000900013Q0004603Q0009000100124A2Q0100024Q009601025Q0020480102000200012Q00F000036Q00682Q01000300012Q000C012Q00017Q00023Q0003043Q007461736B03043Q007761697401073Q0012652Q0100013Q00202Q0001000100024Q00028Q0001000200014Q000100016Q000100028Q00017Q00013Q00030E3Q0073652Q6C496E50726F6772652Q7300033Q00124A012Q00014Q005C012Q00024Q000C012Q00017Q00693Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030B3Q00434F4E4649475F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C6503093Q004661726D54722Q657300030A3Q004661726D53746F6E6573030E3Q0054656C65706F727448656967687403063Q006E756D62657203133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B03113Q004C656769744D6F75736543617074757265030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203103Q004661726D54722Q6573456E61626C656403113Q004661726D53746F6E6573456E61626C6564030E3Q005461726765745069636B4D6F646503063Q0072616E646F6D03073Q006E656172657374030C3Q0054656C65706F72744D6F646503063Q00736D2Q6F746803073Q00696E7374616E7403103Q0054656C65706F72745374657053697A6503043Q006D61746803053Q00636C616D7003053Q00666C2Q6F72027Q0040026Q00444003113Q0054656C65706F72745374657044656C6179027B14AE47E17A943F026Q00E03F03133Q0054656C65706F7274536D2Q6F746853702Q6564026Q33C33F030B3Q00412Q7461636B44656C617903103Q00426C6F636B65645A6F6E65734C697374031B3Q00646573657269616C697A65426C6F636B65645A6F6E65734C69737403193Q006E6F726D616C697A65426C6F636B65645A6F6E65734C69737403093Q00457370436F6C6F727303123Q0073657269616C697A65457370436F6C6F7273030A3Q00457370456E61626C656403083Q0045737054722Q657303093Q0045737053746F6E6573030A3Q00457370506C6179657273030C3Q004573705265736F7572636573030A3Q00457370447261676F6E73030A3Q004573705472616365727303083Q004573704E616D6573030B3Q004573705465787453697A6503113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B54726164657303103Q0052656E646572336444697361626C656403023Q005F4703083Q00726E64725F6469732Q0103123Q004175746F52656E64657233644F6E4661726D03123Q00426C61636B5363722Q656E4F7665726C6179030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A65026Q003440026Q005E4003113Q00426C6F636B65645A6F6E6543656E746572026Q00084003043Q0074797065028Q0003063Q0063656E746572026Q00F03F03043Q0073697A6503113Q0044454641554C545F5A4F4E455F53495A4503073Q00656E61626C656403043Q006E616D6503013Q004C03113Q007A6F6E655F64656661756C745F6E616D6503023Q00203103073Q00566563746F72332Q033Q006E6577030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03063Q00737472696E6703153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F70030A3Q0055694C616E677561676503053Q006C6F77657203023Q00656E03023Q00727503083Q005569585363616C6503093Q005569584F2Q6673657403083Q005569595363616C6503093Q005569594F2Q66736574030A3Q0073617665645569506F7303053Q005544696D32026Q003040025Q00E070C000DD012Q00124A012Q00014Q00B53Q0001000200061E012Q000900013Q0004603Q0009000100124A012Q00023Q00124A2Q0100034Q0079012Q000200020006493Q000A000100010004603Q000A00012Q000C012Q00013Q00124A012Q00043Q0002352Q016Q00B33Q0002000100061E012Q001400013Q0004603Q0014000100124A010200054Q00F0000300014Q00790102000200020026CD00020015000100060004603Q001500012Q000C012Q00013Q0020480102000100070026A00002001B000100080004603Q001B00010020480102000100090026CD0002001B000100080004603Q001B000100124A010200053Q00204801030001000A2Q00790102000200020026A0000200220001000B0004603Q0022000100204801020001000A00128F0002000A3Q00124A010200053Q00204801030001000C2Q00790102000200020026A0000200290001000B0004603Q0029000100204801020001000C00128F0002000C3Q00204801020001000D0026CD0002002E000100080004603Q002E000100204801020001000D00128F0002000D3Q00204801020001000E0026CD00020033000100080004603Q0033000100204801020001000E00128F0002000E3Q00204801020001000F0026CD00020038000100080004603Q0038000100204801020001000F00128F0002000F3Q0020480102000100100026CD0002003D000100080004603Q003D000100204801020001001000128F000200103Q0020480102000100110026CD00020042000100080004603Q0042000100204801020001001100128F000200113Q00124A010200053Q0020480103000100122Q00790102000200020026A0000200490001000B0004603Q0049000100204801020001001200128F000200123Q00124A010200053Q0020480103000100132Q00790102000200020026A0000200500001000B0004603Q0050000100204801020001001300128F000200133Q0020480102000100140026CD00020055000100080004603Q0055000100204801020001001400128F000200143Q0020480102000100150026CD0002005A000100080004603Q005A000100204801020001001500128F000200153Q0020480102000100160026CD00020060000100170004603Q006000010020480102000100160026A000020062000100180004603Q0062000100204801020001001600128F000200163Q0020480102000100190026CD000200680001001A0004603Q006800010020480102000100190026A00002006A0001001B0004603Q006A000100204801020001001900128F000200193Q00124A010200053Q00204801030001001C2Q00790102000200020026A0000200790001000B0004603Q0079000100124A0102001D3Q0020B600020002001E00122Q0003001D3Q00202Q00030003001F00202Q00040001001C4Q00030002000200122Q000400203Q00122Q000500216Q00020005000200122Q0002001C3Q00124A010200053Q0020480103000100222Q00790102000200020026A0000200860001000B0004603Q0086000100124A0102001D3Q00207300020002001E00202Q00030001002200122Q000400233Q00122Q000500246Q00020005000200122Q000200223Q00044Q0093000100124A010200053Q0020480103000100252Q00790102000200020026A0000200930001000B0004603Q0093000100124A0102001D3Q0020AE01020002001E00202Q00030001002500102Q00030026000300122Q000400233Q00122Q000500246Q00020005000200122Q000200223Q00124A010200053Q0020480103000100272Q00790102000200020026A00002009A0001000B0004603Q009A000100204801020001002700128F000200273Q00124A010200053Q0020480103000100282Q00790102000200020026A0000200A3000100060004603Q00A3000100124A010200293Q0020480103000100282Q007901020002000200128F000200283Q00124A0102002A4Q002801020001000100124A010200053Q00204801030001002B2Q00790102000200020026A0000200B1000100060004603Q00B1000100124A0102002C3Q00204801030001002B2Q0079010200020002000649000200B0000100010004603Q00B0000100124A0102002B3Q00128F0002002B3Q00204801020001002D0026CD000200B6000100080004603Q00B6000100204801020001002D00128F0002002D3Q00204801020001002E0026CD000200BB000100080004603Q00BB000100204801020001002E00128F0002002E3Q00204801020001002F0026CD000200C0000100080004603Q00C0000100204801020001002F00128F0002002F3Q0020480102000100300026CD000200C5000100080004603Q00C5000100204801020001003000128F000200303Q0020480102000100310026CD000200CA000100080004603Q00CA000100204801020001003100128F000200313Q0020480102000100320026CD000200CF000100080004603Q00CF000100204801020001003200128F000200323Q0020480102000100330026CD000200D4000100080004603Q00D4000100204801020001003300128F000200333Q0020480102000100340026CD000200D9000100080004603Q00D9000100204801020001003400128F000200343Q00124A010200053Q0020480103000100352Q00790102000200020026A0000200E00001000B0004603Q00E0000100204801020001003500128F000200353Q0020480102000100360026CD000200E5000100080004603Q00E5000100204801020001003600128F000200363Q0020480102000100370026CD000200EA000100080004603Q00EA000100204801020001003700128F000200373Q0020480102000100380026CD000200F0000100080004603Q00F0000100204801020001003800128F000200383Q0004603Q00FB000100124A010200393Q00204801020002003A0026CD000200FB000100080004603Q00FB000100124A010200393Q00204801020002003A0026CD000200F90001003B0004603Q00F900012Q007100026Q006B010200013Q00128F000200383Q00204801020001003C0026CD00022Q002Q0100080004604Q002Q0100204801020001003C00128F0002003C3Q00204801020001003D0026CD000200052Q0100080004603Q00052Q0100204801020001003D00128F0002003D3Q00204801020001003E0026CD0002000A2Q0100080004603Q000A2Q0100204801020001003E00128F0002003E3Q00204801020001003F0026CD0002000F2Q0100080004603Q000F2Q0100204801020001003F00128F0002003F3Q0020480102000100400026CD000200142Q0100080004603Q00142Q0100204801020001004000128F000200403Q0020480102000100410026CD000200192Q0100080004603Q00192Q0100204801020001004100128F000200413Q00124A010200053Q0020480103000100422Q00790102000200020026A0000200282Q01000B0004603Q00282Q0100124A0102001D3Q0020B600020002001E00122Q0003001D3Q00202Q00030003001F00202Q0004000100424Q00030002000200122Q000400433Q00122Q000500446Q00020005000200122Q000200423Q00124A010200053Q0020480103000100452Q00790102000200020026A00002005D2Q0100060004603Q005D2Q010020480102000100452Q0019000200023Q000E670046005D2Q0100020004603Q005D2Q0100124A010200473Q00124A010300284Q00790102000200020026A00002003A2Q0100060004603Q003A2Q0100124A010200284Q0019000200023Q0026A0000200532Q0100480004603Q00532Q012Q0070010200014Q00F300033Q00044Q000400033Q00202Q00050001004500202Q00050005004A00202Q00060001004500202Q00060006002000202Q00070001004500202Q0007000700464Q00040003000100103201030049000400124A010400423Q000649000400492Q0100010004603Q00492Q0100124A0104004C3Q0010320103004B00040030BB0003004D003B00122Q0004004F3Q00122Q000500506Q00040002000200122Q000500516Q00040004000500102Q0003004E00044Q00020001000100128F000200283Q00124A010200523Q00203100020002005300202Q00030001004500202Q00030003004A00202Q00040001004500202Q00040004002000202Q00050001004500202Q0005000500464Q00020005000200122Q000200453Q0020480102000100540026CD000200622Q0100080004603Q00622Q0100204801020001005400128F000200543Q00124A010200053Q0020480103000100552Q00790102000200020026A0000200692Q01000B0004603Q00692Q0100204801020001005500128F000200553Q00124A010200053Q0020480103000100562Q00790102000200020026A0000200702Q0100570004603Q00702Q0100204801020001005600128F000200563Q0020480102000100580026CD000200752Q0100080004603Q00752Q0100204801020001005800128F000200583Q00124A010200053Q0020480103000100592Q00790102000200020026A0000200872Q01000B0004603Q00872Q0100124A0102001D3Q0020B600020002001E00122Q0003001D3Q00202Q00030003001F00202Q0004000100594Q00030002000200122Q0004004A3Q00122Q000500446Q00020005000200122Q000200593Q00124A010200593Q00204F00020002005B00128F0002005A3Q00204801020001005C0026CD0002008C2Q0100080004603Q008C2Q0100204801020001005C00128F0002005C3Q00204801020001005D0026CD000200912Q0100080004603Q00912Q0100204801020001005D00128F0002005D3Q00124A010200053Q00204801030001005E2Q00790102000200020026A0000200A02Q0100570004603Q00A02Q0100204801020001005E00202401020002005F2Q00790102000200020026A00002009E2Q0100600004603Q009E2Q0100127C010200603Q0006490002009F2Q0100010004603Q009F2Q0100127C010200613Q00128F0002005E3Q00124A010200053Q0020480103000100622Q00790102000200020026CD000200B42Q01000B0004603Q00B42Q0100124A010200053Q0020480103000100632Q00790102000200020026CD000200B42Q01000B0004603Q00B42Q0100124A010200053Q0020480103000100642Q00790102000200020026CD000200B42Q01000B0004603Q00B42Q0100124A010200053Q0020480103000100652Q00790102000200020026A0000200DC2Q01000B0004603Q00DC2Q0100124A010200673Q00209600020002005300122Q000300053Q00202Q0004000100624Q00030002000200262Q000300BE2Q01000B0004603Q00BE2Q01002048010300010062000649000300BF2Q0100010004603Q00BF2Q0100127C010300483Q00124A010400053Q0020480105000100632Q00790104000200020026A0000400C72Q01000B0004603Q00C72Q01002048010400010063000649000400C82Q0100010004603Q00C82Q0100127C010400683Q00124A010500053Q0020480106000100642Q00790105000200020026A0000500D02Q01000B0004603Q00D02Q01002048010500010064000649000500D12Q0100010004603Q00D12Q0100127C010500243Q00124A010600053Q0020480107000100652Q00790106000200020026A0000600D92Q01000B0004603Q00D92Q01002048010600010065000649000600DA2Q0100010004603Q00DA2Q0100127C010600694Q00DD00020006000200128F000200664Q000C012Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030B3Q00434F4E4649475F46494C4500083Q0012FB3Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00043Q0003043Q007469636B030D3Q006C6173745761726E696E674174025Q00804640030C3Q006661726D5761726E696E677302113Q001259010200016Q00020001000200122Q000300026Q000300033Q00062Q0003000C00013Q0004603Q000C000100124A010300024Q000A000300034Q004800030002000300263E0003000C000100030004603Q000C00012Q000C012Q00013Q00124A010300024Q008401033Q000200124A010300044Q008401033Q00012Q000C012Q00017Q00023Q00030C3Q006661726D5761726E696E67730001033Q00124A2Q0100013Q0020372Q013Q00022Q000C012Q00017Q00083Q0003053Q007061697273030C3Q006661726D5761726E696E677303053Q007461626C6503063Q00696E7365727403043Q00E280A22003043Q00736F727403063Q00636F6E63617403013Q000A00194Q0070016Q00124A2Q0100013Q00124A010200024Q00B30001000200030004603Q000C000100124A010600033Q0020480106000600042Q00F000075Q00127C010800054Q00F0000900054Q000B0108000800092Q00680106000800010006A200010005000100020004603Q0005000100124A2Q0100033Q0020482Q01000100062Q00F000026Q00E300010002000100124A2Q0100033Q0020482Q01000100072Q00F000025Q00127C010300084Q00512Q0100034Q00C700016Q000C012Q00017Q00033Q0003053Q0073746F6E6503133Q0053746F6E6554656C65706F7274486569676874030E3Q0054656C65706F727448656967687401073Q0026A03Q0004000100010004603Q0004000100124A2Q0100024Q005C2Q0100023Q00124A2Q0100034Q005C2Q0100024Q000C012Q00017Q00093Q0003103Q004661726D54722Q6573456E61626C656403113Q004661726D53746F6E6573456E61626C656403013Q004C030B3Q006D6F64655F736561726368030F3Q0063616368656454722Q65436F756E74028Q0003103Q0063616368656453746F6E65436F756E74030A3Q006D6F64655F74722Q6573030B3Q006D6F64655F73746F6E657300313Q00124A012Q00013Q0006493Q000A000100010004603Q000A000100124A012Q00023Q0006493Q000A000100010004603Q000A000100124A012Q00033Q00127C2Q0100044Q0051012Q00014Q00C77Q00124A012Q00053Q000EA70106001400013Q0004603Q0014000100124A012Q00073Q0006493Q0014000100010004603Q0014000100124A012Q00033Q00127C2Q0100084Q0051012Q00014Q00C77Q00124A012Q00073Q000EA70106001E00013Q0004603Q001E000100124A012Q00053Q0006493Q001E000100010004603Q001E000100124A012Q00033Q00127C2Q0100094Q0051012Q00014Q00C77Q00124A012Q00053Q000EA70106002500013Q0004603Q0025000100124A012Q00033Q00127C2Q0100084Q0051012Q00014Q00C77Q00124A012Q00073Q000EA70106002C00013Q0004603Q002C000100124A012Q00033Q00127C2Q0100094Q0051012Q00014Q00C77Q00124A012Q00033Q00127C2Q0100044Q0051012Q00014Q00C78Q000C012Q00017Q00033Q0003123Q0055736572446973636F7264576562682Q6F6B034Q00030B3Q004B45595F574542482Q4F4B000B3Q00124A012Q00013Q00061E012Q000800013Q0004603Q0008000100124A012Q00013Q0026CD3Q0008000100020004603Q0008000100124A012Q00014Q005C012Q00023Q00124A012Q00034Q005C012Q00024Q000C012Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503123Q007363686564756C6553617665436F6E66696700083Q00124A012Q00014Q00B53Q000100020006493Q0005000100010004603Q000500012Q000C012Q00013Q00124A012Q00024Q0028012Q000100012Q000C012Q00017Q000C3Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F4703043Q007479706503103Q004D6178694875624C6F63616C522Q6F7403063Q00737472696E67034Q0003053Q007461626C6503063Q00696E7365727403013Q002F03093Q006D6178692D6875622F01294Q00912Q015Q00122Q000200013Q00122Q000300026Q00020002000200262Q0002000A000100030004603Q000A000100124A010200024Q00B50002000100020006490002000B000100010004603Q000B000100124A010200043Q00124A010300053Q0020480104000200062Q00790103000200020026A00003001B000100070004603Q001B00010020480103000200060026CD0003001B000100080004603Q001B000100124A010300093Q0020B900030003000A4Q000400013Q00202Q00050002000600122Q0006000B6Q00078Q0005000500074Q00030005000100124A010300093Q00206401030003000A4Q000400013Q00122Q0005000C6Q00068Q0005000500064Q00030005000100122Q000300093Q00202Q00030003000A4Q000400016Q00058Q0003000500014Q000100028Q00017Q000D3Q00030D3Q004D6178694875624553504C696203173Q00676574576F726B73706163654D6F64756C65506174687303103Q006D6178692D6875622D6573702E6C756103063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503063Q00697061697273030A3Q006C6F6164737472696E6703113Q00406D6178692D6875622D6573702E6C756103053Q007063612Q6C03043Q007479706503053Q007461626C6500353Q00124A012Q00013Q00061E012Q000500013Q0004603Q0005000100124A012Q00014Q005C012Q00023Q00124A012Q00023Q001211000100038Q0002000200122Q000100043Q00122Q000200056Q00010002000200262Q00010032000100060004603Q0032000100124A2Q0100043Q00124A010200074Q00792Q01000200020026A000010032000100060004603Q0032000100124A2Q0100084Q00F000026Q00B30001000200030004603Q0030000100124A010600074Q00F0000700054Q007901060002000200061E0106003000013Q0004603Q0030000100124A010600093Q00122A000700056Q000800056Q00070002000200122Q0008000A6Q00060008000200062Q0006003000013Q0004603Q0030000100124A0107000B4Q00F0000800064Q00B300070002000800061E0107003000013Q0004603Q0030000100124A0109000C4Q00F0000A00084Q00790109000200020026A0000900300001000D0004603Q0030000100128F000800013Q00124A010900014Q005C010900023Q0006A200010016000100020004603Q001600012Q0091000100014Q005C2Q0100024Q000C012Q00017Q000D3Q0003103Q004D6178694875624368616E67656C6F6703173Q00676574576F726B73706163654D6F64756C65506174687303163Q006D6178692D6875622D6368616E67656C6F672E6C756103063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503063Q00697061697273030A3Q006C6F6164737472696E6703173Q00406D6178692D6875622D6368616E67656C6F672E6C756103053Q007063612Q6C03043Q007479706503053Q007461626C6500353Q00124A012Q00013Q00061E012Q000500013Q0004603Q0005000100124A012Q00014Q005C012Q00023Q00124A012Q00023Q001211000100038Q0002000200122Q000100043Q00122Q000200056Q00010002000200262Q00010032000100060004603Q0032000100124A2Q0100043Q00124A010200074Q00792Q01000200020026A000010032000100060004603Q0032000100124A2Q0100084Q00F000026Q00B30001000200030004603Q0030000100124A010600074Q00F0000700054Q007901060002000200061E0106003000013Q0004603Q0030000100124A010600093Q00122A000700056Q000800056Q00070002000200122Q0008000A6Q00060008000200062Q0006003000013Q0004603Q0030000100124A0107000B4Q00F0000800064Q00B300070002000800061E0107003000013Q0004603Q0030000100124A0109000C4Q00F0000A00084Q00790109000200020026A0000900300001000D0004603Q0030000100128F000800013Q00124A010900014Q005C010900023Q0006A200010016000100020004603Q001600012Q0091000100014Q005C2Q0100024Q000C012Q00017Q00103Q00030A3Q006C6F61644573704C6962030D3Q004D6178694875624553504C696203063Q00747970656F6603073Q007265667265736803083Q0066756E6374696F6E03073Q00656E61626C6564030A3Q00457370456E61626C656403083Q0045737054722Q657303093Q0045737053746F6E6573030A3Q00457370506C6179657273030C3Q004573705265736F7572636573030A3Q00457370447261676F6E73030A3Q004573705472616365727303083Q004573704E616D6573030B3Q004573705465787453697A6503093Q00457370436F6C6F727300243Q00124A012Q00014Q0028012Q0001000100124A012Q00023Q00061E012Q002300013Q0004603Q0023000100124A012Q00033Q00124A2Q0100023Q0020482Q01000100042Q0079012Q000200020026A03Q0023000100050004603Q0023000100124A012Q00023Q0020BC5Q00044Q00013Q000A00122Q000200073Q00102Q00010006000200122Q000200083Q00102Q00010008000200122Q000200093Q00102Q00010009000200122Q0002000A3Q00102Q0001000A000200124A0102000B3Q00100D0001000B000200122Q0002000C3Q00102Q0001000C000200122Q0002000D3Q00102Q0001000D000200122Q0002000E3Q00102Q0001000E000200122Q0002000F3Q00102Q0001000F000200122Q000200103Q0010322Q01001000022Q00E33Q000200012Q000C012Q00017Q000D3Q0003093Q004C6F63616C654C696203173Q00676574576F726B73706163654D6F64756C65506174687303133Q006D6178692D6875622D6C6F63616C652E6C756103063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503063Q00697061697273030A3Q006C6F6164737472696E6703143Q00406D6178692D6875622D6C6F63616C652E6C756103053Q007063612Q6C03043Q007479706503053Q007461626C6500353Q00124A012Q00013Q00061E012Q000500013Q0004603Q0005000100124A012Q00014Q005C012Q00023Q00124A012Q00023Q001211000100038Q0002000200122Q000100043Q00122Q000200056Q00010002000200262Q00010032000100060004603Q0032000100124A2Q0100043Q00124A010200074Q00792Q01000200020026A000010032000100060004603Q0032000100124A2Q0100084Q00F000026Q00B30001000200030004603Q0030000100124A010600074Q00F0000700054Q007901060002000200061E0106003000013Q0004603Q0030000100124A010600093Q00122A000700056Q000800056Q00070002000200122Q0008000A6Q00060008000200062Q0006003000013Q0004603Q0030000100124A0107000B4Q00F0000800064Q00B300070002000800061E0107003000013Q0004603Q0030000100124A0109000C4Q00F0000A00084Q00790109000200020026A0000900300001000D0004603Q0030000100128F000800013Q00124A010900014Q005C010900023Q0006A200010016000100020004603Q001600012Q0091000100014Q005C2Q0100024Q000C012Q00017Q00053Q0003093Q004C6F63616C654C696203063Q00747970656F6603013Q007403083Q0066756E6374696F6E030A3Q0055694C616E677561676501113Q00124A2Q0100013Q00061E2Q01000F00013Q0004603Q000F000100124A2Q0100023Q00124A010200013Q0020480102000200032Q00792Q01000200020026A00001000F000100040004603Q000F000100124A2Q0100013Q00204100010001000300122Q000200056Q00038Q000100036Q00016Q005C012Q00024Q000C012Q00017Q00053Q0003053Q007461626C6503063Q00696E73657274030E3Q006C6F63616C6542696E64696E677303073Q00656C656D656E742Q033Q006B6579020C3Q00061E012Q000B00013Q0004603Q000B000100061E2Q01000B00013Q0004603Q000B000100124A010200013Q00207501020002000200122Q000300036Q00043Q000200102Q000400043Q00102Q0004000500014Q0002000400012Q000C012Q00017Q00103Q0003043Q006E616D6503013Q004C03083Q007461625F686F6D6503053Q007469746C6503083Q007375627469746C65030C3Q007461625F686F6D655F737562030C3Q007461625F73652Q74696E677303103Q007461625F73652Q74696E67735F737562030B3Q007461625F646973636F7264030F3Q007461625F646973636F72645F73756203073Q007461625F657370030B3Q007461625F6573705F737562030D3Q007461625F6368616E67656C6F6703113Q007461625F6368616E67656C6F675F737562030B3Q007461625F63726564697473030F3Q007461625F637265646974735F73756200524Q0008012Q00066Q00013Q000300122Q000200023Q00122Q000300036Q00020002000200102Q00010001000200122Q000200023Q00122Q000300036Q00020002000200102Q00010004000200124A010200023Q00127C010300064Q00790102000200020010322Q01000500022Q007001023Q000300124A010300023Q001242000400076Q00030002000200102Q00020001000300122Q000300023Q00122Q000400076Q00030002000200102Q00020004000300122Q000300023Q00122Q000400086Q0003000200020010320102000500032Q007001033Q000300124A010400023Q001242000500096Q00040002000200102Q00030001000400122Q000400023Q00122Q000500096Q00040002000200102Q00030004000400122Q000400023Q00122Q0005000A6Q0004000200020010320103000500042Q007001043Q000300124A010500023Q0012420006000B6Q00050002000200102Q00040001000500122Q000500023Q00122Q0006000B6Q00050002000200102Q00040004000500122Q000500023Q00122Q0006000C6Q0005000200020010320104000500052Q007001053Q000300124A010600023Q0012420007000D6Q00060002000200102Q00050001000600122Q000600023Q00122Q0007000D6Q00060002000200102Q00050004000600122Q000600023Q00122Q0007000E6Q0006000200020010320105000500062Q007001063Q000300124A010700023Q0012420008000F6Q00070002000200102Q00060001000700122Q000700023Q00122Q0008000F6Q00070002000200102Q00060004000700122Q000700023Q00122Q000800106Q0007000200020010320106000500072Q0036012Q000600012Q005C012Q00024Q000C012Q00017Q00123Q00030A3Q0050484153455F5445585403043Q0069646C6503013Q004C030A3Q0070686173655F69646C6503063Q00736561726368030C3Q0070686173655F73656172636803043Q006D696E65030A3Q0070686173655F6D696E6503043Q0077616974030A3Q0070686173655F7761697403073Q00636F2Q6C656374030D3Q0070686173655F636F2Q6C65637403043Q0073652Q6C030A3Q0070686173655F73652Q6C2Q033Q0068756203093Q0070686173655F68756203063Q0074726176656C030C3Q0070686173655F74726176656C00234Q00EC5Q000800122Q000100033Q00122Q000200046Q00010002000200104Q0002000100122Q000100033Q00122Q000200066Q00010002000200104Q0005000100122Q000100033Q00122Q000200086Q00010002000200104Q0007000100122Q000100033Q00122Q0002000A6Q00010002000200104Q0009000100122Q000100033Q00122Q0002000C6Q00010002000200104Q000B000100122Q000100033Q00122Q0002000E6Q00010002000200104Q000D000100122Q000100033Q00122Q000200106Q00010002000200104Q000F000100122Q000100033Q00122Q000200126Q00010002000200104Q0011000100124Q00018Q00017Q00063Q00030D3Q00646973636F726453746174757303043Q005465787403103Q0063616E557365436F6E66696746696C6503013Q004C03103Q00776562682Q6F6B5F73617665645F6F6B03113Q00776562682Q6F6B5F73617665645F62616400133Q00124A012Q00013Q0006493Q0004000100010004603Q000400012Q000C012Q00013Q00124A012Q00013Q00124A2Q0100034Q00B500010001000200061E2Q01000E00013Q0004603Q000E000100124A2Q0100043Q00127C010200054Q00792Q010002000200064900010011000100010004603Q0011000100124A2Q0100043Q00127C010200064Q00792Q0100020002001032012Q000200012Q000C012Q00017Q00073Q0003113Q006372656469747341626F75744C6162656C03043Q0054657874030C3Q005343524950545F5449544C4503013Q000A03013Q004C030B3Q007363726970745F6C696E65030E3Q00637265646974735F7468616E6B7301133Q00124A2Q0100013Q00064900010004000100010004603Q000400012Q000C012Q00013Q00124A2Q0100013Q00124A010200033Q00127C010300043Q0006A00104000C00013Q0004603Q000C000100124A010400053Q00127C010500064Q007901040002000200127C010500043Q00124A010600053Q00127C010700074Q00790106000200022Q000B0102000200060010322Q01000200022Q000C012Q00017Q00223Q0003063Q00697061697273030E3Q006C6F63616C6542696E64696E677303073Q00656C656D656E7403063Q00506172656E7403043Q005465787403013Q004C2Q033Q006B657903103Q007265667265736850686173655465787403173Q00757064617465446973636F72645374617475735465787403163Q007570646174654372656469747341626F757454657874030D3Q006D616E75616C53652Q6C42746E030B3Q0062746E5F73652Q6C696E67030C3Q0062746E5F73652Q6C5F6E6F77030F3Q0063726564697473546742752Q746F6E03093Q0074675F636F7069656403093Q0074675F62752Q746F6E030C3Q007A6F6E65506C61636542746E030F3Q0062746E5F637562655F706C6163656403103Q0062746E5F6E6F5F636861726163746572030E3Q0062746E5F706C6163655F6375626503023Q00756903063Q00747970656F66030C3Q007365745469746C6548696E7403083Q0066756E6374696F6E030A3Q007469746C655F68696E74030F3Q007365744869646548696E745465787403093Q00686964655F68696E7403103Q00726566726573685461624C6162656C73030A3Q0067657454616244656673030B3Q007365744C616E6775616765030A3Q0055694C616E677561676503103Q00726566726573684B657953746174757303043Q0067656E76030E3Q004D6178694875624B65794761746500923Q00124A012Q00013Q00124A2Q0100024Q00B33Q000200020004603Q0010000100204801050004000300061E0105001000013Q0004603Q0010000100204801050004000300204801050005000400061E0105001000013Q0004603Q0010000100204801050004000300124A010600063Q0020480107000400072Q00790106000200020010320105000500060006A23Q0004000100020004603Q0004000100124A012Q00084Q007D012Q0001000100124Q00098Q0001000100124Q000A8Q0001000100124Q000B3Q00064Q002700013Q0004603Q0027000100124A012Q000B3Q00209C014Q000500122Q000100063Q00122Q0002000C6Q00010002000200064Q0027000100010004603Q0027000100124A012Q000B3Q00124A2Q0100063Q00127C0102000D4Q00792Q0100020002001032012Q0005000100124A012Q000E3Q00061E012Q003600013Q0004603Q0036000100124A012Q000E3Q00209C014Q000500122Q000100063Q00122Q0002000F6Q00010002000200064Q0036000100010004603Q0036000100124A012Q000E3Q00124A2Q0100063Q00127C010200104Q00792Q0100020002001032012Q0005000100124A012Q00113Q00061E012Q004C00013Q0004603Q004C000100124A012Q00113Q00209C014Q000500122Q000100063Q00122Q000200126Q00010002000200064Q004C000100010004603Q004C000100124A012Q00113Q00209C014Q000500122Q000100063Q00122Q000200136Q00010002000200064Q004C000100010004603Q004C000100124A012Q00113Q00124A2Q0100063Q00127C010200144Q00792Q0100020002001032012Q0005000100124A012Q00153Q00061E012Q008500013Q0004603Q0085000100124A012Q00163Q00124A2Q0100153Q0020482Q01000100172Q0079012Q000200020026A03Q005B000100180004603Q005B000100124A012Q00153Q00204F014Q001700122Q000100063Q00122Q000200196Q000100029Q00000100124A012Q00163Q00124A2Q0100153Q0020482Q010001001A2Q0079012Q000200020026A03Q0067000100180004603Q0067000100124A012Q00153Q00204F014Q001A00122Q000100063Q00122Q0002001B6Q000100029Q00000100124A012Q00163Q00124A2Q0100153Q0020482Q010001001C2Q0079012Q000200020026A03Q0072000100180004603Q0072000100124A012Q00153Q002048014Q001C00124A2Q01001D4Q00452Q0100014Q006F5Q000100124A012Q00163Q00124A2Q0100153Q0020482Q010001001E2Q0079012Q000200020026A03Q007C000100180004603Q007C000100124A012Q00153Q002048014Q001E00124A2Q01001F4Q00E33Q0002000100124A012Q00163Q00124A2Q0100153Q0020482Q01000100202Q0079012Q000200020026A03Q0085000100180004603Q0085000100124A012Q00153Q002048014Q00202Q0028012Q0001000100124A012Q00213Q002048014Q002200061E012Q009100013Q0004603Q0091000100124A2Q0100163Q00204801023Q001E2Q00792Q01000200020026A000010091000100180004603Q009100010020482Q013Q001E00124A0102001F4Q00E30001000200012Q000C012Q00017Q00083Q00030A3Q0055694C616E677561676503043Q007479706503063Q00737472696E6703053Q006C6F77657203023Q00656E03023Q00727503123Q00612Q706C794D6178694875624C6F63616C6503123Q007363686564756C6553617665436F6E66696701133Q00124A2Q0100024Q00F000026Q00792Q01000200020026A00001000C000100030004603Q000C00010020242Q013Q00042Q00792Q01000200020026A00001000C000100050004603Q000C000100127C2Q0100053Q0006490001000D000100010004603Q000D000100127C2Q0100063Q00128F000100013Q00123C000100076Q00010001000100122Q000100086Q0001000100016Q00017Q00093Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030E3Q00576F726C6454656C65706F727473030B3Q0054656C65706F7274506164030D3Q0054656C65706F72744D6F64656C2Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734100293Q00123A3Q00013Q00206Q000200122Q000200038Q0002000200064Q0008000100010004603Q000800012Q0091000100014Q005C2Q0100023Q0020242Q013Q000200127C010300044Q00DD0001000300020006490001000F000100010004603Q000F00012Q0091000200024Q005C010200023Q00202401020001000200127C010400054Q00DD00020004000200064900020016000100010004603Q001600012Q0091000300034Q005C010300023Q00202401030002000200127C010500064Q00DD0003000500020006490003001D000100010004603Q001D00012Q0091000400044Q005C010400023Q00202401040003000700127C010600084Q00DD00040006000200061E0104002300013Q0004603Q002300012Q005C010300023Q00202401040003000900126F010600086Q000700016Q000400076Q00049Q0000017Q00033Q0003133Q005669727475616C496E7075744D616E6167657203043Q0067616D65030A3Q004765745365727669636500063Q00124A012Q00023Q002024014Q000300127C010200014Q00DD3Q0002000200128F3Q00014Q000C012Q00017Q00023Q0003133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00073Q00124A012Q00013Q00061E012Q000600013Q0004603Q0006000100124A012Q00023Q0002352Q016Q00E33Q000200012Q000C012Q00013Q00013Q00063Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D65000A3Q0012503Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00033Q0003093Q006D6F75736548656C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00103Q00124A012Q00013Q0006493Q0004000100010004603Q000400012Q000C012Q00013Q00124A012Q00023Q00061E012Q000A00013Q0004603Q000A000100124A012Q00033Q0002352Q016Q00E33Q0002000100124A012Q00033Q0002352Q0100014Q00E33Q000200012Q006B016Q00128F3Q00014Q000C012Q00013Q00023Q00063Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F75736559028Q0003043Q0067616D65000A3Q00122B3Q00013Q00206Q000200122Q000200033Q00122Q000300043Q00122Q000400056Q00055Q00122Q000600063Q00122Q000700058Q000700016Q00017Q00033Q0003063Q00747970656F66030D3Q006D6F7573653172656C6561736503083Q0066756E6374696F6E00083Q00124A012Q00013Q00124A2Q0100024Q0079012Q000200020026A03Q0007000100030004603Q0007000100124A012Q00024Q0028012Q000100012Q000C012Q00017Q00083Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900133Q00124A012Q00013Q002048014Q000200061E012Q000900013Q0004603Q0009000100124A012Q00013Q002048014Q0002002024014Q000300127C010200044Q00DD3Q000200020006493Q000C000100010004603Q000C00012Q000C012Q00013Q00124A2Q0100063Q00205E00010001000700104Q0005000100122Q000100063Q00202Q00010001000700104Q000800016Q00017Q00023Q00030F3Q00426C6F636B65645A6F6E6553697A65027Q004000043Q00124A012Q00013Q0020245Q00022Q005C012Q00024Q000C012Q00017Q00043Q0003113Q00426C6F636B65645A6F6E6543656E74657203163Q00676574426C6F636B65645A6F6E6548616C6653697A6503073Q00566563746F72332Q033Q006E657700193Q00124A012Q00013Q0006493Q0005000100010004603Q000500012Q00913Q00014Q001D3Q00033Q00124A012Q00024Q00B53Q0001000200124A2Q0100013Q00124A010200033Q0020480102000200042Q00F000036Q00F000046Q00F000056Q00DD0002000500022Q004800010001000200124A010200013Q00124A010300033Q0020480103000300042Q00F000046Q00F000056Q00F000066Q00DD0003000600022Q004E0102000200032Q001D000100034Q000C012Q00017Q00133Q0003043Q007479706503053Q007461626C6503043Q0073697A6503043Q006D61746803053Q00636C616D7003053Q00666C2Q6F7203113Q0044454641554C545F5A4F4E455F53495A45026Q003440026Q005E4003073Q00656E61626C6564002Q0103043Q006E616D6503063Q00737472696E67034Q0003013Q004C03113Q007A6F6E655F64656661756C745F6E616D6503013Q002003083Q00746F737472696E67022B3Q00124A010200014Q00F000036Q00790102000200020026CD00020007000100020004603Q000700012Q0091000200024Q005C010200023Q00124A010200043Q00207401020002000500122Q000300043Q00202Q00030003000600202Q00043Q000300062Q0004000F000100010004603Q000F000100124A010400074Q0079010300020002001228000400083Q00122Q000500096Q00020005000200104Q0003000200202Q00023Q000A00262Q000200180001000B0004603Q0018000100309F012Q000A000C00124A010200013Q00204801033Q000D2Q00790102000200020026A0000200200001000E0004603Q0020000100204801023Q000D0026A0000200290001000F0004603Q0029000100124A010200103Q00127C010300114Q007901020002000200127C010300123Q00124A010400134Q00F0000500014Q00790104000200022Q000B010200020004001032012Q000D00022Q005C012Q00024Q000C012Q00017Q00033Q0003103Q00426C6F636B65645A6F6E65734C69737403063Q0069706169727303143Q006E6F726D616C697A65426C6F636B65645A6F6E6500103Q00124A012Q00013Q0006493Q0004000100010004603Q000400012Q0070016Q00128F3Q00013Q00124A012Q00023Q00124A2Q0100014Q00B33Q000200020004603Q000D000100124A010500034Q00F0000600044Q00F0000700034Q00680105000700010006A23Q0009000100020004603Q000900012Q000C012Q00017Q00153Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403043Q007479706503103Q00426C6F636B65645A6F6E65734C69737403053Q007461626C65028Q0003063Q0069706169727303073Q00656E61626C6564010003063Q0063656E74657203043Q0073697A6503113Q0044454641554C545F5A4F4E455F53495A45026Q000840027Q004003073Q00566563746F72332Q033Q006E6577026Q00F03F03013Q005803013Q005903013Q005A03113Q00426C6F636B65645A6F6E6543656E74657203143Q00676574426C6F636B65645A6F6E654D696E4D617801813Q00124A2Q0100013Q00061E2Q01000500013Q0004603Q000500010006493Q0007000100010004603Q000700012Q006B2Q016Q005C2Q0100023Q00124A2Q0100023Q00124A010200034Q00792Q01000200020026A000010058000100040004603Q0058000100124A2Q0100034Q0019000100013Q000EA701050058000100010004603Q0058000100124A2Q0100063Q00124A010200034Q00B30001000200030004603Q005400010020480106000500070026A000060018000100080004603Q001800010004603Q0054000100204801060005000900204801070005000A0006490007001D000100010004603Q001D000100124A0107000B3Q00124A010800024Q00F0000900064Q00790108000200020026A000080054000100040004603Q005400012Q0019000800063Q000E67000C0054000100080004603Q0054000100202400080007000D0012090009000E3Q00202Q00090009000F00202Q000A0006001000202Q000B0006000D00202Q000C0006000C4Q0009000C000200122Q000A000E3Q00202Q000A000A000F4Q000B00086Q000C00086Q000D00086Q000A000D00024Q000A0009000A00122Q000B000E3Q00202Q000B000B000F4Q000C00086Q000D00086Q000E00086Q000B000E00024Q000B0009000B00202Q000C3Q001100202Q000D000A001100062Q000D00540001000C0004603Q00540001002048010C3Q0011002048010D000B0011000690000C00540001000D0004603Q00540001002048010C3Q0012002048010D000A0012000690000D00540001000C0004603Q00540001002048010C3Q0012002048010D000B0012000690000C00540001000D0004603Q00540001002048010C3Q0013002048010D000A0013000690000D00540001000C0004603Q00540001002048010C3Q0013002048010D000B0013000690000C00540001000D0004603Q005400012Q006B010C00014Q005C010C00023Q0006A200010014000100020004603Q001400012Q006B2Q016Q005C2Q0100023Q00124A2Q0100143Q0006490001005D000100010004603Q005D00012Q006B2Q016Q005C2Q0100023Q00124A2Q0100154Q00472Q010001000200061E2Q01006300013Q0004603Q0063000100064900020065000100010004603Q006500012Q006B01036Q005C010300023Q00204801033Q00110020480104000100110006900004007D000100030004603Q007D000100204801033Q00110020480104000200110006900003007D000100040004603Q007D000100204801033Q00120020480104000100120006900004007D000100030004603Q007D000100204801033Q00120020480104000200120006900003007D000100040004603Q007D000100204801033Q00130020480104000100130006900004007D000100030004603Q007D000100204801033Q001300204801040002001300063C01030002000100040004603Q007E00012Q007100036Q006B010300014Q005C010300024Q000C012Q00017Q00083Q0003103Q00426C6F636B65645A6F6E65734C69737403053Q007461626C6503063Q0072656D6F7665028Q0003113Q00426C6F636B65645A6F6E6543656E74657203173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q0072656275696C645A6F6E65734C697374554903123Q007363686564756C6553617665436F6E66696701173Q00124A2Q0100014Q000A000100013Q00064900010005000100010004603Q000500012Q000C012Q00013Q00124A2Q0100023Q0020482Q010001000300124A010200014Q00F000036Q00682Q010003000100124A2Q0100014Q0019000100013Q0026A000010010000100040004603Q001000012Q0091000100013Q00128F000100053Q00124A2Q0100064Q00282Q010001000100123C000100076Q00010001000100122Q000100086Q0001000100016Q00017Q001A3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403103Q00426C6F636B65645A6F6E65734C697374026Q00F03F03053Q007461626C6503063Q00696E7365727403063Q0063656E74657203083Q00506F736974696F6E03013Q005803013Q005903013Q005A03043Q0073697A6503113Q0044454641554C545F5A4F4E455F53495A4503073Q00656E61626C65642Q0103043Q006E616D6503013Q004C03113Q007A6F6E655F64656661756C745F6E616D6503013Q002003083Q00746F737472696E6703113Q00426C6F636B65645A6F6E6543656E74657203173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q0072656275696C645A6F6E65734C697374554903123Q007363686564756C6553617665436F6E666967003A3Q00124A012Q00013Q002048014Q000200061E012Q000900013Q0004603Q0009000100124A012Q00013Q002048014Q0002002024014Q000300127C010200044Q00DD3Q000200020006493Q000D000100010004603Q000D00012Q006B2Q016Q005C2Q0100023Q00124A2Q0100053Q00064900010011000100010004603Q001100012Q00702Q015Q00128F000100053Q00120B000100056Q000100013Q00202Q00010001000600122Q000200073Q00202Q00020002000800122Q000300056Q00043Q00044Q000500033Q00202Q00063Q000A00202Q00060006000B00202Q00073Q000A00202Q00070007000C00202Q00083Q000A00202Q00080008000D4Q0005000300010010320104000900050012470005000F3Q00102Q0004000E000500302Q00040010001100122Q000500133Q00122Q000600146Q00050002000200122Q000600153Q00122Q000700166Q000800016Q0007000200024Q00050005000700102Q0004001200054Q00020004000100202Q00023Q000A00122Q000200173Q00122Q000200186Q00020001000100122Q000200196Q00020001000100122Q0002001A6Q0002000100014Q000200016Q000200028Q00017Q00053Q0003103Q00426C6F636B65645A6F6E65734C69737403113Q00426C6F636B65645A6F6E6543656E74657203173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q0072656275696C645A6F6E65734C697374554903123Q007363686564756C6553617665436F6E666967000B4Q00047Q00124Q00019Q003Q00124Q00023Q00124Q00038Q0001000100123C3Q00048Q0001000100124Q00058Q000100016Q00017Q004A3Q0003083Q00496E7374616E63652Q033Q006E657703053Q004672616D6503043Q004E616D6503093Q005A6F6E65436172645F03043Q0053697A6503053Q005544696D32026Q00F03F028Q00026Q00584003103Q004261636B67726F756E64436F6C6F723303063Q00434F4C4F525303053Q0070616E656C030F3Q00426F7264657253697A65506978656C030B3Q004C61796F75744F7264657203063Q00506172656E7403093Q00612Q64436F726E6572026Q00204003073Q0054657874426F78025Q00805DC0026Q003A4003083Q00506F736974696F6E026Q00244003043Q006361726403103Q00436C656172546578744F6E466F637573010003043Q00466F6E7403043Q00456E756D030A3Q00476F7468616D426F6C6403083Q005465787453697A65026Q002640030A3Q0054657874436F6C6F723303043Q0074657874030F3Q00506C616365686F6C6465725465787403013Q004C03153Q007A6F6E655F6E616D655F706C616365686F6C64657203043Q005465787403043Q006E616D65034Q00030E3Q005465787458416C69676E6D656E7403043Q004C656674026Q00184003093Q00554950612Q64696E67030B3Q0050612Q64696E674C65667403043Q005544696D030A3Q005465787442752Q746F6E026Q004440026Q003640026Q0058C003073Q00656E61626C656403063Q00612Q63656E7403093Q00746F2Q676C654F2Q66030F3Q004175746F42752Q746F6E436F6C6F72026Q003040026Q0032C0026Q00E03F026Q0020C0026Q00084003113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E656374026Q0048C0026Q002C402Q033Q0072656403023Q00C39703093Q00466F6375734C6F7374026Q0034C0026Q004A4003163Q004261636B67726F756E645472616E73706172656E6379030A3Q006D616B65536C6964657203103Q00736C696465725F637562655F73697A65026Q003440026Q005E4003043Q0073697A6503113Q0044454641554C545F5A4F4E455F53495A45030B012Q001262010300013Q00202Q00030003000200122Q000400036Q00030002000200122Q000400056Q000500016Q00040004000500102Q00030004000400122Q000400073Q00207301040004000200122Q000500083Q00122Q000600093Q00122Q000700093Q00122Q0008000A6Q00040008000200101A00030006000400122Q0004000C3Q00202Q00040004000D00102Q0003000B000400302Q0003000E000900102Q0003000F000100102Q000300103Q00122Q000400116Q000500033Q00122Q000600124Q004901040006000100122Q000400013Q00202Q00040004000200122Q000500136Q00040002000200122Q000500073Q00207301050005000200122Q000600083Q00122Q000700143Q00122Q000800093Q00122Q000900156Q00050009000200103201040006000500124A010500073Q00207301050005000200122Q000600093Q00122Q000700173Q00122Q000800093Q00122Q000900126Q00050009000200103201040016000500124A0105000C3Q0020480105000500180010320104000B000500309F0104000E000900309F01040019001A00124A0105001C3Q00204801050005001B00204801050005001D0010320104001B000500309F0104001E001F0012620005000C3Q00202Q00050005002100102Q00040020000500122Q000500233Q00122Q000600246Q00050002000200102Q00040022000500202Q00050002002600062Q00050043000100010004603Q0043000100127C010500273Q00103201040025000500126E0105001C3Q00202Q00050005002800202Q00050005002900102Q00040028000500102Q00040010000300122Q000500116Q000600043Q00122Q0007002A6Q00050007000100122Q000500013Q00202Q00050005000200122Q0006002B6Q00050002000200122Q0006002D3Q00202Q00060006000200122Q000700093Q00122Q000800126Q00060008000200102Q0005002C000600102Q00050010000400122Q000600013Q00202Q00060006000200122Q0007002E6Q00060002000200122Q000700073Q00202Q00070007000200122Q000800093Q00122Q0009002F3Q00122Q000A00093Q00122Q000B00306Q0007000B000200102Q00060006000700122Q000700073Q00202Q00070007000200122Q000800083Q00122Q000900313Q00122Q000A00093Q00122Q000B00176Q0007000B000200102Q00060016000700202Q00070002003200262Q000700730001001A0004603Q0073000100124A0107000C3Q00204801070007003300064900070075000100010004603Q0075000100124A0107000C3Q0020480107000700340010320106000B000700309F0106000E000900309F01060025002700309F01060035001A00103201060010000300124A010700114Q00F0000800063Q00127C0109001F4Q004901070009000100122Q000700013Q00202Q00070007000200122Q000800036Q00070002000200122Q000800073Q00207301080008000200122Q000900093Q00122Q000A00363Q00122Q000B00093Q00122Q000C00366Q0008000C00020010320107000600080020480108000200320026CD000800960001001A0004603Q0096000100124A010800073Q00207301080008000200122Q000900083Q00122Q000A00373Q00122Q000B00383Q00122Q000C00396Q0008000C00020006490008009D000100010004603Q009D000100124A010800073Q00207301080008000200122Q000900093Q00122Q000A003A3Q00122Q000B00383Q00122Q000C00396Q0008000C000200103201070016000800129D0008000C3Q00202Q00080008002100102Q0007000B000800302Q0007000E000900102Q00070010000600122Q000800116Q000900073Q00122Q000A00126Q0008000A000100068800083Q000100032Q00F03Q00024Q00F03Q00064Q00F03Q00073Q00204801090006003B00202401090009003C000688000B0001000100022Q00F03Q00024Q00F03Q00084Q00490109000B000100122Q000900013Q00202Q00090009000200122Q000A002E6Q00090002000200122Q000A00073Q002073010A000A000200122Q000B00093Q00122Q000C002F3Q00122Q000D00093Q00122Q000E00156Q000A000E000200103201090006000A00124A010A00073Q002073010A000A000200122Q000B00083Q00122Q000C003D3Q00122Q000D00093Q00122Q000E00126Q000A000E000200103201090016000A00124A010A000C3Q002048010A000A00180010320109000B000A00309F0109000E000900124A010A001C3Q002048010A000A001B002048010A000A001D0010320109001B000A00309F0109001E003E00124A010A000C3Q00206D000A000A003F00102Q00090020000A00302Q00090025004000302Q00090035001A00102Q00090010000300122Q000A00116Q000B00093Q00122Q000C002A6Q000A000C000100202Q000A0009003B002024010A000A003C000688000C0002000100012Q00F03Q00014Q0068010A000C0001002048010A00040041002024010A000A003C000688000C0003000100032Q00F03Q00044Q00F03Q00024Q00F03Q00014Q003D000A000C000100122Q000A00013Q00202Q000A000A000200122Q000B00036Q000A0002000200122Q000B00073Q00202Q000B000B000200122Q000C00083Q00122Q000D00423Q00122Q000E00093Q00122Q000F00436Q000B000F000200102Q000A0006000B00122Q000B00073Q00202Q000B000B000200122Q000C00093Q00122Q000D00173Q00122Q000E00093Q00122Q000F002F6Q000B000F000200102Q000A0016000B00302Q000A0044000800102Q000A0010000300122Q000B00456Q000C000A3Q00122Q000D00093Q00122Q000E00233Q00122Q000F00466Q000E0002000200122Q000F00473Q00122Q001000483Q00202Q00110002004900062Q001100062Q0100010004603Q00062Q0100124A0111004A3Q00068800120004000100012Q00F03Q00023Q00127C011300464Q0068010B001300012Q000C012Q00013Q00053Q00143Q0003073Q00656E61626C6564010003103Q004261636B67726F756E64436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E7403093Q00746F2Q676C654F2Q66030C3Q0054772Q656E5365727669636503063Q0043726561746503093Q0054772Q656E496E666F2Q033Q006E657702B81E85EB51B8BE3F03083Q00506F736974696F6E03053Q005544696D32026Q00F03F026Q0032C0026Q00E03F026Q0020C0028Q00026Q00084003043Q00506C6179002F4Q0096016Q002048014Q00010026A03Q0005000100020004603Q000500012Q00718Q006B012Q00014Q00962Q0100013Q00061E012Q000D00013Q0004603Q000D000100124A010200043Q0020480102000200050006490002000F000100010004603Q000F000100124A010200043Q0020480102000200060010322Q01000300020012272Q0100073Q00202Q0001000100084Q000300023Q00122Q000400093Q00202Q00040004000A00122Q0005000B6Q0004000200024Q00053Q000100064Q002300013Q0004603Q0023000100124A0106000D3Q00207301060006000A00122Q0007000E3Q00122Q0008000F3Q00122Q000900103Q00122Q000A00116Q0006000A00020006490006002A000100010004603Q002A000100124A0106000D3Q00207301060006000A00122Q000700123Q00122Q000800133Q00122Q000900103Q00122Q000A00116Q0006000A00020010320105000C00062Q00DD0001000500020020242Q01000100142Q00E30001000200012Q000C012Q00017Q00043Q0003073Q00656E61626C6564010003173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E666967000F4Q0096017Q00962Q015Q0020482Q01000100010026CD00010006000100020004603Q000600012Q007100016Q006B2Q0100013Q001032012Q000100012Q0096012Q00014Q0028012Q0001000100123C3Q00038Q0001000100124Q00048Q000100016Q00017Q00013Q0003113Q0072656D6F7665426C6F636B65645A6F6E6500043Q00124A012Q00014Q00962Q016Q00E33Q000200012Q000C012Q00017Q000B3Q0003043Q005465787403043Q006773756203043Q005E25732B034Q0003043Q0025732B2403043Q006E616D6503013Q004C03113Q007A6F6E655F64656661756C745F6E616D6503013Q002003083Q00746F737472696E6703123Q007363686564756C6553617665436F6E666967001F4Q0043016Q00206Q000100206Q000200122Q000200033Q00122Q000300048Q0003000200206Q000200122Q000200053Q00122Q000300048Q000300024Q000100013Q00264Q000F000100040004603Q000F00010006A00102001700013Q0004603Q0017000100124A010200073Q0012EB000300086Q00020002000200122Q000300093Q00122Q0004000A6Q000500026Q0004000200024Q0002000200040010322Q01000600022Q002600018Q000200013Q00202Q00020002000600102Q00010001000200122Q0001000B6Q0001000100016Q00017Q00053Q0003043Q0073697A6503043Q006D61746803053Q00666C2Q6F7203173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E666967010B4Q000E00015Q00122Q000200023Q00202Q0002000200034Q00038Q00020002000200102Q00010001000200123C000100046Q00010001000100122Q000100056Q0001000100016Q00017Q00093Q0003123Q007A6F6E65734C697374436F6E7461696E657203063Q00697061697273030B3Q004765744368696C6472656E2Q033Q00497341030C3Q0055494C6973744C61796F757403073Q0044657374726F7903193Q006E6F726D616C697A65426C6F636B65645A6F6E65734C69737403103Q00426C6F636B65645A6F6E65734C697374030E3Q006372656174655A6F6E654361726400213Q00124A012Q00013Q0006493Q0004000100010004603Q000400012Q000C012Q00013Q00124A012Q00023Q001256000100013Q00202Q0001000100034Q000100029Q00000200044Q0011000100202401050004000400127C010700054Q00DD00050007000200064900050011000100010004603Q001100010020240105000400062Q00E30005000200010006A23Q000A000100020004603Q000A000100124A012Q00074Q0028012Q0001000100124A012Q00023Q00124A2Q0100084Q00B33Q000200020004603Q001E000100124A010500093Q00124A010600014Q00F0000700034Q00F0000800044Q00680105000800010006A23Q0019000100020004603Q001900012Q000C012Q00017Q00023Q00030D3Q006765744E6F646543656E74657203123Q006973506F73496E426C6F636B65645A6F6E65010A3Q00124A2Q0100014Q00F000026Q00792Q010002000200063200020008000100010004603Q0008000100124A010200024Q00F0000300014Q00790102000200022Q005C010200024Q000C012Q00017Q00083Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203083Q00496E7374616E63652Q033Q006E657703063Q00466F6C64657203043Q004E616D6503063Q00506172656E7400113Q0012873Q00013Q00206Q000200122Q000200038Q0002000200064Q000F000100010004603Q000F000100124A2Q0100043Q0020482Q010001000500127C010200064Q00792Q01000200022Q00F03Q00013Q00124A2Q0100033Q001032012Q0007000100124A2Q0100013Q001032012Q000800012Q005C012Q00024Q000C012Q00017Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403053Q007063612Q6C000C3Q00124A012Q00013Q00061E012Q000800013Q0004603Q0008000100124A012Q00023Q0002352Q016Q00E33Q000200012Q00917Q00128F3Q00013Q00124A012Q00023Q0002352Q0100014Q00E33Q000200012Q000C012Q00013Q00023Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403073Q0044657374726F7900043Q00124A012Q00013Q002024014Q00022Q00E33Q000200012Q000C012Q00017Q00043Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203073Q0044657374726F7900093Q0012E43Q00013Q00206Q000200122Q000200038Q0002000200064Q000800013Q0004603Q000800010020242Q013Q00042Q00E30001000200012Q000C012Q00017Q002F3Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203043Q007479706503103Q00426C6F636B65645A6F6E65734C69737403053Q007461626C65028Q0003063Q0069706169727303063Q0063656E74657203043Q0073697A6503113Q0044454641554C545F5A4F4E455F53495A4503073Q00656E61626C65640100026Q00084003083Q00496E7374616E63652Q033Q006E657703043Q005061727403043Q004E616D65030B3Q00416E746954505A6F6E655F03083Q00416E63686F7265642Q01030A3Q0043616E436F2Q6C69646503083Q0043616E517565727903083Q0043616E546F756368030A3Q0043617374536861646F7703083Q004D6174657269616C03043Q00456E756D030A3Q00466F7263654669656C6403053Q00436F6C6F7203063Q00436F6C6F723303073Q0066726F6D524742025Q00E06F40025Q00805140025Q00406040030C3Q005472616E73706172656E6379020AD7A3703D0AE73F02295C8FC2F528EC3F03043Q0053697A6503073Q00566563746F723303063Q00434672616D65026Q00F03F027Q004003063Q00506172656E7403113Q00426C6F636B65645A6F6E6543656E74657203153Q00626C6F636B65645A6F6E6556697375616C50617274030A3Q00416E746954505A6F6E65030F3Q00426C6F636B65645A6F6E6553697A65009C3Q00124A012Q00013Q0006493Q0006000100010004603Q0006000100124A012Q00024Q0028012Q000100012Q000C012Q00013Q00124A012Q00034Q00CB3Q0001000200122Q000100026Q00010001000100122Q000100036Q0001000100026Q00013Q00122Q000100043Q00122Q000200056Q00010002000200262Q00010067000100060004603Q0067000100124A2Q0100054Q0019000100013Q000EA701070067000100010004603Q0067000100124A2Q0100083Q00124A010200054Q00B30001000200030004603Q0064000100204801060005000900204801070005000A0006490007001F000100010004603Q001F000100124A0107000B3Q00204801080005000C0026A0000800230001000D0004603Q002300012Q007100086Q006B010800013Q00124A010900044Q00F0000A00064Q00790109000200020026A000090064000100060004603Q006400012Q0019000900063Q000E67000E0064000100090004603Q0064000100124A0109000F3Q00206B00090009001000122Q000A00116Q00090002000200122Q000A00136Q000B00046Q000A000A000B00102Q00090012000A00302Q00090014001500302Q00090016000D00302Q00090017000D00309F01090018000D00309500090019000D00122Q000A001B3Q00202Q000A000A001A00202Q000A000A001C00102Q0009001A000A00062Q0008004700013Q0004603Q0047000100124A010A001E3Q002063000A000A001F00122Q000B00203Q00122Q000C00213Q00122Q000D00216Q000A000D0002000649000A004D000100010004603Q004D000100124A010A001E3Q002063000A000A001F00122Q000B00223Q00122Q000C00223Q00122Q000D00226Q000A000D00020010320109001D000A00061E0108005300013Q0004603Q0053000100127C010A00243Q000649000A0054000100010004603Q0054000100127C010A00253Q00103201090023000A00124A010A00273Q002048010A000A00102Q00F0000B00074Q00F0000C00074Q00F0000D00074Q00DD000A000D000200103201090026000A00124A010A00283Q002048010A000A0010002048010B00060029002048010C0006002A002048010D0006000E2Q00DD000A000D000200103201090028000A0010320109002B3Q0006A20001001A000100020004603Q001A00012Q000C012Q00013Q00124A2Q01002C3Q0006490001006B000100010004603Q006B00012Q000C012Q00013Q00124A2Q01000F3Q00201C2Q010001001000122Q000200116Q00010002000200122Q0001002D3Q00122Q0001002D3Q00302Q00010012002E00122Q0001002D3Q00302Q00010014001500122Q0001002D3Q00302Q00010016000D00122Q0001002D3Q00302Q00010017000D00122Q0001002D3Q00302Q00010018000D00122Q0001002D3Q00302Q00010019000D00122Q0001002D3Q00122Q0002001B3Q00202Q00020002001A00202Q00020002001C00102Q0001001A000200122Q0001002D3Q00122Q0002001E3Q00202Q00020002001F00122Q000300203Q00122Q000400213Q00122Q000500216Q00020005000200102Q0001001D000200122Q0001002D3Q00302Q00010023002400122Q0001002D3Q00122Q000200273Q00202Q00020002001000122Q0003002F3Q00122Q0004002F3Q00122Q0005002F6Q00020005000200102Q00010026000200122Q0001002D3Q00122Q000200283Q00202Q00020002001000122Q0003002C6Q00020002000200102Q00010028000200122Q0001002D3Q00102Q0001002B8Q00017Q00013Q0003163Q00612Q64426C6F636B65645A6F6E654174506C6179657200043Q00124A012Q00014Q0009012Q00014Q00C78Q000C012Q00017Q00053Q0003063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747902083Q0010E73Q0001000100122Q000200033Q00202Q00020002000400104Q0002000200122Q000200033Q00202Q00020002000400104Q000500026Q00017Q00083Q0003123Q006973506F73496E426C6F636B65645A6F6E6503063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403063Q00434672616D652Q033Q006E657703153Q00612Q706C79487270434672616D65496E7374616E74022A3Q00124A010200014Q00F000036Q007901020002000200061E0102000700013Q0004603Q000700012Q006B01026Q005C010200023Q00124A010200023Q00204801020002000300061E0102001000013Q0004603Q0010000100124A010200023Q00204801020002000300202401020002000400127C010400054Q00DD00020004000200061E0102001400013Q0004603Q001400010006493Q0016000100010004603Q001600012Q006B01036Q005C010300023Q00061E2Q01001F00013Q0004603Q001F000100124A010300063Q0020550003000300074Q00048Q000500016Q00030005000200062Q00030023000100010004603Q0023000100124A010300063Q0020480103000300072Q00F000046Q007901030002000200124A010400084Q0057010500026Q000600036Q0004000600014Q000400016Q000400028Q00017Q00173Q0003123Q006973506F73496E426C6F636B65645A6F6E6503063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030C3Q0054656C65706F72744D6F646503063Q00736D2Q6F746803143Q0074656C65706F7274487270546F496E7374616E7403083Q00506F736974696F6E03093Q004D61676E6974756465029A5Q99D93F03153Q00612Q706C79487270434672616D65496E7374616E7403063Q00434672616D652Q033Q006E657703043Q00556E6974028Q00029A5Q99B93F03123Q0073686F756C644661726D436F6E74696E756503043Q006D6174682Q033Q006D696E03103Q0054656C65706F72745374657053697A6503113Q00696E74652Q7275707469626C655761697403113Q0054656C65706F72745374657044656C6179025B3Q00124A010200014Q00F000036Q007901020002000200061E0102000700013Q0004603Q000700012Q006B01026Q005C010200023Q00124A010200023Q00204801020002000300061E0102001000013Q0004603Q0010000100124A010200023Q00204801020002000300202401020002000400127C010400054Q00DD00020004000200061E0102001400013Q0004603Q001400010006493Q0016000100010004603Q001600012Q006B01036Q005C010300023Q00124A010300063Q0026CD0003001D000100070004603Q001D000100124A010300084Q00F000046Q0051010300044Q00C700035Q0020480103000200092Q00F000046Q004800050004000300204801060005000A00263E0006002C0001000B0004603Q002C000100124A0107000C4Q00B1000800023Q00122Q0009000D3Q00202Q00090009000E4Q000A00046Q0009000A6Q00073Q00012Q006B010700014Q005C010700023Q00204801070005000F00127C010800103Q00208001090006001100061701080051000100090004603Q0051000100061E2Q01003A00013Q0004603Q003A000100124A010900124Q00F0000A00014Q00790109000200020006490009003A000100010004603Q003A00012Q006B01096Q005C010900023Q00124A010900133Q00204801090009001400124A010A00154Q0048000B000600082Q00DD0009000B00022Q004E01080008000900124A010A000C4Q00F0000B00023Q00124A010C000D3Q002048010C000C000E2Q000C000D000700082Q004E010D0003000D2Q0018010C000D6Q000A3Q000100122Q000A00163Q00122Q000B00176Q000C00016Q000A000C000200062Q000A002E000100010004603Q002E00012Q006B010A6Q005C010A00023Q0004603Q002E000100124A0109000C4Q00B1000A00023Q00122Q000B000D3Q00202Q000B000B000E4Q000C00046Q000B000C6Q00093Q00012Q006B010900014Q005C010900024Q000C012Q00017Q00053Q0003063Q00736D2Q6F746803123Q0074656C65706F7274487270546F537465707303053Q0072756E496403143Q0074656C65706F7274487270546F496E7374616E7403063Q006C2Q6F6B417402123Q00064900010004000100010004603Q000400012Q007001026Q00F0000100023Q00204801020001000100061E0102000C00013Q0004603Q000C000100124A010200024Q00F000035Q0020480104000100032Q0051010200044Q00C700025Q00124A010200044Q00F000035Q0020480104000100052Q0051010200044Q00C700026Q000C012Q00017Q000A3Q0003043Q007469636B03123Q0073686F756C644661726D436F6E74696E756503043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F0002293Q00124A010200014Q00B50002000100022Q004E010200023Q00124A010300014Q00B50003000100020006170103001F000100020004603Q001F000100061E2Q01001000013Q0004603Q0010000100124A010300024Q00F0000400014Q007901030002000200064900030010000100010004603Q001000012Q006B01036Q005C010300023Q00124A010300033Q00204101030003000400122Q000400053Q00202Q00040004000600122Q000500073Q00122Q000600053Q00202Q00060006000800122Q000700093Q00122Q000800016Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q000300010026CD000100260001000A0004603Q0026000100124A010300024Q00F0000400014Q00790103000200020004603Q002700012Q007100036Q006B010300014Q005C010300024Q000C012Q00017Q000A3Q00030F3Q006D616E75616C53652Q6C546F6B656E03043Q007469636B030E3Q0073652Q6C496E50726F6772652Q7303043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F01283Q00124A2Q0100013Q00124A010200024Q00B50002000100022Q004E010200023Q00124A010300024Q00B50003000100020006170103001F000100020004603Q001F000100124A010300013Q00069C0001000E000100030004603Q000E000100124A010300033Q00064900030010000100010004603Q001000012Q006B01036Q005C010300023Q00124A010300043Q00204101030003000500122Q000400063Q00202Q00040004000700122Q000500083Q00122Q000600063Q00202Q00060006000900122Q0007000A3Q00122Q000800026Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q0004000100124A010300013Q00069C00010024000100030004603Q0024000100124A010300033Q0004603Q002600012Q007100036Q006B010300014Q005C010300024Q000C012Q00017Q000B3Q0003143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274001F3Q00124A012Q00014Q00B53Q0001000200061E012Q000F00013Q0004603Q000F00010020482Q013Q00030012F1000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100023Q00122Q000100026Q000100023Q00124A2Q0100083Q0020482Q010001000900061E2Q01001800013Q0004603Q0018000100124A2Q0100083Q0020482Q01000100090020242Q010001000A00127C0103000B4Q00DD00010003000200061E2Q01001E00013Q0004603Q001E000100204801020001000300128F000200023Q00124A010200024Q005C010200024Q000C012Q00017Q00123Q00030B3Q00687562506F736974696F6E03143Q0067657454656C65706F7274537061776E5061727403083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q0069706169727303053Q00537061776E030D3Q00537061776E4C6F636174696F6E2Q033Q0048756203093Q00776F726B7370616365030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734103123Q0063617074757265487562506F736974696F6E026Q00144000483Q00124A012Q00013Q00061E012Q000500013Q0004603Q0005000100124A012Q00014Q005C012Q00023Q00124A012Q00024Q00B53Q0001000200061E012Q001400013Q0004603Q001400010020482Q013Q00030012F1000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100013Q00122Q000100016Q000100023Q00124A2Q0100084Q0014010200033Q00122Q000300093Q00122Q0004000A3Q00122Q0005000B6Q0002000300012Q00B30001000200030004603Q003A000100124A0106000C3Q00202401060006000D2Q00F0000800054Q00DD00060008000200061E0106003A00013Q0004603Q003A000100202401070006000E00127C0109000F4Q00DD00070009000200061E0107002900013Q0004603Q002900010006A00107002D000100060004603Q002D000100202401070006001000127C0109000F4Q006B010A00014Q00DD0007000A000200061E0107003A00013Q0004603Q003A00010020480108000700030012F1000900043Q00202Q00090009000500122Q000A00063Q00122Q000B00073Q00122Q000C00066Q0009000C00024Q00080008000900122Q000800013Q00122Q000800016Q000800023Q0006A20001001C000100020004603Q001C000100124A2Q0100114Q00B500010001000200064900010046000100010004603Q0046000100124A2Q0100043Q00206300010001000500122Q000200063Q00122Q000300123Q00122Q000400066Q0001000400022Q005C2Q0100024Q000C012Q00017Q000D3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030E3Q00676574487562506F736974696F6E03073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030F3Q004855425F4E4541525F52414449555300283Q00124A012Q00013Q002048014Q000200061E012Q000900013Q0004603Q0009000100124A012Q00013Q002048014Q0002002024014Q000300127C010200044Q00DD3Q0002000200124A2Q0100054Q00B500010001000200061E012Q000F00013Q0004603Q000F000100064900010011000100010004603Q001100012Q006B01026Q005C010200023Q00124A010200063Q00206901020002000700202Q00033Q000800202Q00030003000900202Q00040001000A00202Q00053Q000800202Q00050005000B4Q00020005000200122Q000300063Q00202Q00030003000700202Q00040001000900202Q00050001000A00202Q00060001000B4Q0003000600024Q00040002000300202Q00040004000C00122Q0005000D3Q00062Q00040002000100050004603Q002500012Q007100046Q006B010400014Q005C010400024Q000C012Q00017Q000D3Q0003093Q0069734E65617248756203143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q000840030E3Q00676574487562506F736974696F6E030C3Q0054656C65706F72744D6F646503063Q00736D2Q6F7468030D3Q0074656C65706F7274487270546F03053Q0072756E496401263Q00124A2Q0100014Q00B500010001000200061E2Q01000600013Q0004603Q000600012Q006B2Q0100014Q005C2Q0100024Q0091000100013Q00124A010200024Q00B500020001000200061E0102001600013Q0004603Q001600010020480103000200040012AD010400053Q00202Q00040004000600122Q000500073Q00122Q000600083Q00122Q000700076Q0004000700024Q00030003000400122Q000300033Q00122Q000100033Q00044Q0019000100124A010300094Q00B50003000100022Q00F0000100033Q00124A0103000A3Q0026CD0003001D0001000B0004603Q001D00012Q007100036Q006B010300013Q00124A0104000C4Q00F0000500014Q007001063Q00020010320106000B00030010320106000D4Q0051010400064Q00C700046Q000C012Q00017Q000E4Q00030E3Q0048756257616974456E61626C656403093Q006661726D50686173652Q033Q0068756203103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q0063752Q72656E7454617267657450617274030D3Q0074656C65706F7274546F487562030C3Q004855425F574149545F4D494E03043Q006D61746803063Q0072616E646F6D030C3Q004855425F574149545F4D415803113Q00696E74652Q7275707469626C6557616974022A3Q0026A000010003000100010004603Q000300012Q006B2Q0100013Q00124A010200023Q00064900020008000100010004603Q000800012Q006B010200014Q005C010200023Q00127C010200043Q0012CA000200033Q00122Q000200056Q00020001000100122Q000200066Q00020001000100122Q000200076Q0002000100014Q000200023Q00122Q000200083Q00062Q0001001B00013Q0004603Q001B000100124A010200094Q00F000036Q00790102000200020006490002001B000100010004603Q001B00012Q006B01026Q005C010200023Q00124A0102000A3Q00124A0103000B3Q00204801030003000C2Q00B500030001000200124A0104000D3Q00124A0105000A4Q00480004000400052Q000C0003000300042Q004E01020002000300124A0103000E4Q00F0000400024Q00F000056Q0051010300054Q00C700036Q000C012Q00017Q00033Q00030B3Q00687562526573745761697403093Q006661726D506861736503043Q0069646C65010C3Q00124A2Q0100014Q00F000026Q00792Q010002000200064900010007000100010004603Q000700012Q006B2Q016Q005C2Q0100023Q00127C2Q0100033Q00128F000100024Q006B2Q0100014Q005C2Q0100024Q000C012Q00017Q00023Q0003073Q00557365464B6579030B3Q006175746F4641637469766500063Q00124A012Q00013Q0006493Q0004000100010004603Q0004000100124A012Q00024Q005C012Q00024Q000C012Q00017Q00033Q00030C3Q0073686F756C645072652Q734603133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C000F3Q00124A012Q00014Q00B53Q000100020006493Q0005000100010004603Q000500012Q000C012Q00013Q00124A012Q00023Q00061E012Q000B00013Q0004603Q000B000100124A012Q00033Q0002352Q016Q00E33Q0002000100124A012Q00033Q0002352Q0100014Q00E33Q000200012Q000C012Q00013Q00023Q00093Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D6503043Q007461736B03043Q007761697402B81E85EB51B89E3F00173Q0012F53Q00013Q00206Q00024Q000200013Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q0005000100124Q00073Q002048014Q000800127C2Q0100094Q00E33Q000200010012503Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00023Q0003063Q006B657974617003043Q00564B5F4600043Q00124A012Q00013Q00124A2Q0100024Q00E33Q000200012Q000C012Q00017Q00063Q0003113Q004C656769744D6F7573654361707475726503133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C03063Q00747970656F66030C3Q006D6F7573656D6F766561627303083Q0066756E6374696F6E021B3Q00124A010200013Q00061E0102000700013Q0004603Q0007000100061E012Q000700013Q0004603Q0007000100064900010008000100010004603Q000800012Q000C012Q00013Q00124A010200023Q00061E0102001000013Q0004603Q0010000100124A010200033Q00068800033Q000100022Q00F08Q00F03Q00014Q00E300020002000100124A010200043Q00124A010300054Q00790102000200020026A00002001A000100060004603Q001A000100124A010200033Q00068800030001000100022Q00F08Q00F03Q00014Q00E30002000200012Q000C012Q00013Q00023Q00033Q0003133Q005669727475616C496E7075744D616E6167657203123Q0053656E644D6F7573654D6F76654576656E7403043Q0067616D6500073Q001254012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400038Q000400016Q00017Q00013Q00030C3Q006D6F7573656D6F766561627300053Q0012663Q00016Q00018Q000200018Q000200016Q00017Q000C3Q00028Q0003113Q006D6F76654D6F757365546F5363722Q656E03093Q006D6F75736548656C6403043Q006D6174682Q033Q00616273030A3Q00686F6C644D6F75736558027Q0040030A3Q00686F6C644D6F7573655903103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C03113Q004C656769744D6F7573654361707475726502343Q0006A00102000300013Q0004603Q0003000100127C010200013Q00064900010006000100010004603Q0006000100127C2Q0100014Q00F03Q00023Q001285000200026Q00038Q000400016Q00020004000100122Q000200033Q00062Q0002001D00013Q0004603Q001D000100124A010200043Q00200001020002000500122Q000300066Q000300036Q00020002000200262Q0002001D000100070004603Q001D000100124A010200043Q00200001020002000500122Q000300086Q0003000300014Q00020002000200262Q0002001D000100070004603Q001D00012Q000C012Q00013Q00124A010200094Q002801020001000100124A0102000A3Q00061E0102002800013Q0004603Q0028000100124A0102000B3Q00068800033Q000100022Q00F08Q00F03Q00014Q00E30002000200010004603Q002E000100124A0102000C3Q00061E0102002E00013Q0004603Q002E000100124A0102000B3Q000235010300014Q00E30002000200012Q006B010200013Q00128F000200034Q00F000025Q00128F000100083Q00128F000200064Q000C012Q00013Q00023Q00043Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D65000A3Q00129E012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q000700016Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F757365317072652Q7303083Q0066756E6374696F6E00083Q00124A012Q00013Q00124A2Q0100024Q0079012Q000200020026A03Q0007000100030004603Q0007000100124A012Q00024Q0028012Q000100012Q000C012Q00017Q00053Q0003113Q006D6F76654D6F757365546F5363722Q656E03103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C03113Q004C656769744D6F75736543617074757265021A3Q00124A010200014Q00F000036Q00F0000400014Q006801020004000100124A010200024Q002801020001000100124A010200033Q00061E0102001300013Q0004603Q0013000100061E012Q001300013Q0004603Q0013000100061E2Q01001300013Q0004603Q0013000100124A010200043Q00068800033Q000100022Q00F08Q00F03Q00014Q00E30002000200010004603Q0019000100124A010200053Q00061E0102001900013Q0004603Q0019000100124A010200043Q000235010300014Q00E30002000200012Q000C012Q00013Q00023Q00093Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D65030B3Q00412Q7461636B44656C6179029A5Q99A93F027B14AE47E17A843F03043Q007461736B03043Q007761697400203Q0012863Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q0007000100124Q00053Q000E2Q0003000F00013Q0004603Q000F000100127C012Q00063Q0006493Q0010000100010004603Q0010000100127C012Q00073Q000EA70103001600013Q0004603Q0016000100124A2Q0100083Q0020482Q01000100092Q00F000026Q00E300010002000100124A2Q0100013Q0020242Q01000100022Q009601036Q0096010400013Q00127C010500034Q006B01065Q00124A010700043Q00127C010800034Q00682Q01000800012Q000C012Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F75736531636C69636B03083Q0066756E6374696F6E00083Q00124A012Q00013Q00124A2Q0100024Q0079012Q000200020026A03Q0007000100030004603Q0007000100124A012Q00024Q0028012Q000100012Q000C012Q00017Q00073Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D65726103143Q00576F726C64546F56696577706F7274506F696E74030A3Q0047756953657276696365030B3Q00476574477569496E73657403013Q005803013Q005901163Q0006493Q0004000100010004603Q000400012Q0091000100014Q005C2Q0100023Q00124A2Q0100013Q0020482Q01000100020006490001000A000100010004603Q000A00012Q0091000200024Q005C010200023Q0020240102000100032Q00F000046Q00DD00020004000200124A010300043Q0020240103000300052Q00790103000200020020480104000200060020480105000200070020480106000300072Q004E0105000500062Q001D000400034Q000C012Q00017Q00083Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D657261030A3Q0047756953657276696365030B3Q00476574477569496E736574030C3Q0056696577706F727453697A6503013Q0058026Q00E03F03013Q005900123Q00124A012Q00013Q002048014Q00020006493Q0006000100010004603Q000600012Q0091000100014Q005C2Q0100023Q00124A2Q0100033Q0020052Q01000100044Q00010002000200202Q00023Q000500202Q00030002000600202Q00030003000700202Q00040002000800202Q00040004000700202Q0005000100084Q0004000400054Q000300038Q00017Q00043Q002Q033Q0049734103083Q00426173655061727403083Q00506F736974696F6E03163Q0046696E6446697273744368696C64576869636849734101143Q0006493Q0004000100010004603Q000400012Q0091000100014Q005C2Q0100023Q0020242Q013Q000100127C010300024Q00DD00010003000200061E2Q01000B00013Q0004603Q000B00010020482Q013Q00032Q005C2Q0100023Q0020242Q013Q000400127C010300024Q006B010400014Q00DD00010004000200061E2Q01001300013Q0004603Q001300010020480102000100032Q005C010200024Q000C012Q00017Q00093Q00030B3Q0041696D4174546172676574030A3Q006163746976654E6F6465030F3Q0067657454617267657443656E74657203103Q006163746976655461726765744B696E6403113Q0063752Q72656E745461726765745061727403063Q00506172656E74030F3Q0067657450617274506F736974696F6E030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73012B3Q00124A010200013Q00061E0102001800013Q0004603Q0018000100124A010200023Q00061E0102000B00013Q0004603Q000B000100124A010200033Q00124A010300023Q00124A010400044Q00DD0002000400022Q00F0000100023Q00064900010018000100010004603Q0018000100124A010200053Q00061E0102001800013Q0004603Q0018000100124A010200053Q00204801020002000600061E0102001800013Q0004603Q0018000100124A010200073Q00124A010300054Q00790102000200022Q00F0000100023Q0006490001001E000100010004603Q001E000100124A010200074Q00F000036Q00790102000200022Q00F0000100023Q00124A010200084Q00F0000300014Q00B300020002000300064900020027000100010004603Q0027000100124A010400094Q00470104000100052Q00F0000300054Q00F0000200044Q00F0000400024Q00F0000500034Q001D000400034Q000C012Q00017Q00013Q00030B3Q0069734E6F6465416C69766502053Q00121B010200016Q00038Q000200036Q00029Q0000017Q00013Q00030B3Q00676574486974626F78657302053Q00121B010200016Q00038Q000200036Q00029Q0000017Q00013Q00030D3Q006765744E6F646543656E74657202053Q00121B010200016Q00038Q000200036Q00029Q0000017Q00013Q00030D3Q006765744E6F64654865616C746802053Q00121B010200016Q00038Q000200036Q00029Q0000017Q00073Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403043Q004465616403053Q0056616C75652Q0103063Q004865616C7468028Q00011E3Q0020242Q013Q000100127C010300024Q00DD00010003000200064900010007000100010004603Q000700012Q006B01026Q005C010200023Q00202401020001000100127C010400034Q00DD00020004000200061E0102001100013Q0004603Q001100010020480103000200040026A000030011000100050004603Q001100012Q006B01036Q005C010300023Q00202401030001000100127C010500064Q00DD00030005000200061E0103001B00013Q0004603Q001B000100204801040003000400267A0004001B000100070004603Q001B00012Q006B01046Q005C010400024Q006B010400014Q005C010400024Q000C012Q00017Q00043Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403063Q004865616C746803053Q0056616C7565010F3Q0006320001000500013Q0004603Q000500010020242Q013Q000100127C010300024Q00DD0001000300020006320002000A000100010004603Q000A000100202401020001000100127C010400034Q00DD00020004000200061E0102000E00013Q0004603Q000E00010020480103000200042Q005C010300024Q000C012Q00017Q00043Q00030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365029Q00074Q00C97Q00124Q00019Q003Q00124Q00023Q00124Q00043Q00124Q00038Q00017Q00083Q0003073Q00557365464B6579030B3Q006175746F46416374697665030F3Q006765745461726765744865616C746803043Q007469636B030F3Q00737475636B4C6173744865616C746800030A3Q00737475636B53696E6365030F3Q00535455434B5F465F5345434F4E445302223Q00124A010200013Q00061E0102000600013Q0004603Q000600012Q006B01025Q00128F000200024Q000C012Q00013Q00124A010200034Q00F000036Q00F0000400014Q00DD0002000400020006490002000D000100010004603Q000D00012Q000C012Q00013Q00124A010300044Q00B500030001000200124A010400053Q0026CD00040015000100060004603Q0015000100124A010400053Q0006170102001A000100040004603Q001A000100128F000200053Q00128F000300074Q006B01045Q00128F000400023Q0004603Q0021000100124A010400074Q004800040003000400124A010500083Q00069000050021000100040004603Q002100012Q006B010400013Q00128F000400024Q000C012Q00017Q00083Q0003063Q00697061697273030B3Q004765744368696C6472656E03043Q004E616D6503063Q00486974626F782Q033Q0049734103083Q00426173655061727403053Q007461626C6503063Q00696E7365727401174Q00702Q015Q001256000200013Q00202Q00033Q00024Q000300046Q00023Q000400044Q001300010020480107000600030026A000070013000100040004603Q0013000100202401070006000500127C010900064Q00DD00070009000200061E0107001300013Q0004603Q0013000100124A010700073Q0020480107000700082Q00F0000800014Q00F0000900064Q00680107000900010006A200020006000100020004603Q000600012Q005C2Q0100024Q000C012Q00017Q00033Q002Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C645768696368497341010C3Q0020242Q013Q000100127C010300024Q00DD00010003000200061E2Q01000600013Q0004603Q000600012Q005C012Q00023Q0020242Q013Q000300126F010300026Q000400016Q000100046Q00019Q0000017Q00063Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403083Q00506F736974696F6E030B3Q00676574486974626F786573028Q00026Q00F03F01113Q0020242Q013Q000100127C010300024Q00DD00010003000200061E2Q01000700013Q0004603Q000700010020480102000100032Q005C010200023Q00124A010200044Q00F000036Q00790102000200022Q0019000300023Q000EA701050010000100030004603Q001000010020480103000200060020480103000300032Q005C010300024Q000C012Q00017Q000D3Q0003053Q007063612Q6C03063Q0069706169727303053Q007461626C6503063Q00696E7365727403103Q004661726D54722Q6573456E61626C656403113Q004661726D53746F6E6573456E61626C6564030F3Q00707573684661726D5761726E696E6703073Q006E6F5F6D6F6465032D3Q00D092D18BD0BAD0BBD18ED187D0B5D0BDD18B20D0B2D181D0B520D182D0B8D0BFD18B20D186D0B5D0BBD0B5D0B9028Q00030A3Q006E6F5F7461726765747303253Q00D09DD0B5D18220D186D0B5D0BBD0B5D0B920D0B4D0BBD18F20D0B4D0BED0B1D18BD187D0B803103Q00636C6561724661726D5761726E696E6700374Q0070017Q00702Q015Q00124A010200013Q00068800033Q000100022Q00F08Q00F03Q00014Q00890002000200014Q00025Q00122Q000300026Q000400026Q00058Q000600016Q0004000200012Q00B30003000200050004603Q001A000100124A010800024Q00F0000900074Q00B300080002000A0004603Q0018000100124A010D00033Q002048010D000D00042Q00F0000E00024Q00F0000F000C4Q0068010D000F00010006A200080013000100020004603Q001300010006A20003000F000100020004603Q000F000100124A010300053Q00064900030027000100010004603Q0027000100124A010300063Q00064900030027000100010004603Q0027000100124A010300073Q00127C010400083Q00127C010500094Q00680103000500010004603Q003500012Q0019000300023Q0026A00003002F0001000A0004603Q002F000100124A010300073Q00127C0104000B3Q00127C0105000C4Q00680103000500010004603Q0035000100124A0103000D3Q00120F0004000B6Q00030002000100122Q0003000D3Q00122Q000400086Q0003000200012Q005C010200024Q000C012Q00013Q00013Q00183Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030F3Q00707573684661726D5761726E696E67030F3Q006E6F5F696E746572616374696F6E7303203Q00D09DD0B5D18220496E746572616374696F6E7320D0B220776F726B737061636503103Q00636C6561724661726D5761726E696E6703053Q004E6F64657303083Q006E6F5F6E6F64657303173Q00D09DD0B5D18220D0BFD0B0D0BFD0BAD0B8204E6F64657303103Q004661726D54722Q6573456E61626C656403043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C69766503133Q0069734E6F6465496E426C6F636B65645A6F6E6503053Q007461626C6503063Q00696E7365727403043Q006E6F646503043Q006B696E6403043Q0074722Q6503113Q004661726D53746F6E6573456E61626C656403093Q005265736F757263657303053Q0073746F6E65005C3Q00123A3Q00013Q00206Q000200122Q000200038Q0002000200064Q000B000100010004603Q000B000100124A2Q0100043Q00127C010200053Q00127C010300064Q00682Q01000300012Q000C012Q00013Q00124A2Q0100073Q0012AB000200056Q00010002000100202Q00013Q000200122Q000300086Q00010003000200062Q00010018000100010004603Q0018000100124A010200043Q00127C010300093Q00127C0104000A4Q00680102000400012Q000C012Q00013Q00124A010200073Q00127C010300094Q00E300020002000100124A0102000B3Q00061E0102003B00013Q0004603Q003B000100202401020001000200127C0104000C4Q00DD00020004000200061E0102003B00013Q0004603Q003B000100124A0103000D3Q00202401040002000E2Q00FA000400054Q001800033Q00050004603Q0039000100124A0108000F4Q00F0000900074Q007901080002000200061E0108003900013Q0004603Q0039000100124A010800104Q00F0000900074Q007901080002000200064900080039000100010004603Q0039000100124A010800113Q0020570008000800124Q00098Q000A3Q000200102Q000A0013000700302Q000A001400154Q0008000A00010006A200030028000100020004603Q0028000100124A010200163Q00061E0102005B00013Q0004603Q005B000100202401020001000200127C010400174Q00DD00020004000200061E0102005B00013Q0004603Q005B000100124A0103000D3Q00202401040002000E2Q00FA000400054Q001800033Q00050004603Q0059000100124A0108000F4Q00F0000900074Q007901080002000200061E0108005900013Q0004603Q0059000100124A010800104Q00F0000900074Q007901080002000200064900080059000100010004603Q0059000100124A010800113Q0020570008000800124Q000900016Q000A3Q000200102Q000A0013000700302Q000A001400184Q0008000A00010006A200030048000100020004603Q004800012Q000C012Q00017Q00043Q00028Q0003053Q007063612Q6C030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E74000D3Q00127C012Q00013Q00127C2Q0100013Q00124A010200023Q00068800033Q000100022Q00F08Q00F03Q00014Q006E00020002000100124Q00033Q00122Q000100046Q00028Q000300016Q000200038Q00013Q00013Q000A3Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E7303053Q004E6F64657303043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C697665026Q00F03F03093Q005265736F757263657300363Q00123A3Q00013Q00206Q000200122Q000200038Q0002000200064Q0007000100010004603Q000700012Q000C012Q00013Q0020242Q013Q000200127C010300044Q00DD0001000300020006490001000D000100010004603Q000D00012Q000C012Q00013Q00202401020001000200127C010400054Q00DD00020004000200061E0102002100013Q0004603Q0021000100124A010300063Q0020240104000200072Q00FA000400054Q001800033Q00050004603Q001F000100124A010800084Q00F0000900074Q007901080002000200061E0108001F00013Q0004603Q001F00012Q009601085Q0020650008000800092Q001201085Q0006A200030017000100020004603Q0017000100202401030001000200127C0105000A4Q00DD00030005000200061E0103003500013Q0004603Q0035000100124A010400063Q0020240105000300072Q00FA000500064Q001800043Q00060004603Q0033000100124A010900084Q00F0000A00084Q007901090002000200061E0109003300013Q0004603Q003300012Q0096010900013Q0020650009000900092Q0012010900013Q0006A20004002B000100020004603Q002B00012Q000C012Q00017Q00103Q00028Q00030E3Q005461726765745069636B4D6F646503063Q0072616E646F6D03043Q006D617468026Q00F03F030E3Q00676574487562506F736974696F6E03063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403083Q00506F736974696F6E03063Q00697061697273030F3Q0067657454617267657443656E74657203043Q006E6F646503043Q006B696E6403093Q004D61676E6974756465013D4Q001900015Q0026A000010005000100010004603Q000500012Q0091000100014Q005C2Q0100023Q00124A2Q0100023Q0026A00001000F000100030004603Q000F000100124A2Q0100043Q0020602Q010001000300122Q000200056Q00038Q0001000300024Q00013Q00014Q000100023Q00124A2Q0100064Q00B500010001000200124A010200073Q00204801020002000800061E0102001A00013Q0004603Q001A000100124A010200073Q00204801020002000800202401020002000900127C0104000A4Q00DD00020004000200061E0102001F00013Q0004603Q001F00010006490001001F000100010004603Q001F00010020482Q010002000B00064900010023000100010004603Q0023000100204801033Q00052Q005C010300024Q0091000300043Q00124A0105000C4Q00F000066Q00B30005000200070004603Q0036000100124A010A000D3Q002048010B0009000E002048010C0009000F2Q00DD000A000C000200061E010A003600013Q0004603Q003600012Q0048000B000A0001002048010B000B001000061E0104003400013Q0004603Q00340001000617010B0036000100040004603Q003600012Q00F0000300094Q00F00004000B3Q0006A200050028000100020004603Q002800010006A00105003B000100030004603Q003B000100204801053Q00052Q005C010500024Q000C012Q00017Q00043Q00030C3Q00706174726F6C506F696E747303053Q007063612Q6C030B3Q00706174726F6C496E646578026Q00F03F00084Q0070016Q00128F3Q00013Q00124A012Q00023Q0002352Q016Q00E33Q0002000100127C012Q00043Q00128F3Q00034Q000C012Q00013Q00013Q00083Q0003063Q00697061697273030F3Q0067657456616C696454617267657473030F3Q0067657454617267657443656E74657203043Q006E6F646503043Q006B696E6403053Q007461626C6503063Q00696E73657274030C3Q00706174726F6C506F696E747300133Q001261012Q00013Q00122Q000100026Q000100019Q00000200044Q0010000100124A010500033Q0020480106000400040020480107000400052Q00DD00050007000200061E0105001000013Q0004603Q0010000100124A010600063Q00204801060006000700124A010700084Q00F0000800054Q00680106000800010006A23Q0005000100020004603Q000500012Q000C012Q00017Q001A3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030C3Q00706174726F6C506F696E7473028Q00030B3Q00706174726F6C496E64657803073Q00566563746F72332Q033Q006E657703183Q0067657454656C65706F7274486569676874466F724B696E6403103Q006163746976655461726765744B696E64026Q00F03F030B3Q00736561726368416E676C65026Q66D63F030C3Q00736561726368526164697573026Q007940026Q005440026Q002E4003083Q00506F736974696F6E03043Q006D6174682Q033Q00636F732Q033Q0073696E03063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900573Q00124A012Q00013Q002048014Q000200061E012Q000900013Q0004603Q0009000100124A012Q00013Q002048014Q0002002024014Q000300127C010200044Q00DD3Q000200020006493Q000C000100010004603Q000C00012Q000C012Q00014Q0091000100013Q00124A010200054Q0019000200023Q000EA701060029000100020004603Q0029000100124A010200053Q00124A010300074Q000A00020002000300061E0102001F00013Q0004603Q001F000100124A010300083Q0020CE00030003000900122Q000400063Q00122Q0005000A3Q00122Q0006000B6Q00050002000200122Q000600066Q0003000600024Q00010002000300124A010300073Q00206500030003000C00128F000300073Q00124A010300073Q00124A010400054Q0019000400043Q00061701040029000100030004603Q0029000100127C0103000C3Q00128F000300073Q0006490001004B000100010004603Q004B000100124A0102000D3Q00206500020002000E00128F0002000D3Q00124A0102000F3Q000EA701100034000100020004603Q0034000100127C010200113Q00128F0002000F3Q0004603Q0037000100124A0102000F3Q00206500020002001200128F0002000F3Q00204801023Q001300127B010300083Q00202Q00030003000900122Q000400143Q00202Q00040004001500122Q0005000D6Q00040002000200122Q0005000F6Q00040004000500122Q0005000A3Q00122Q0006000B4Q007901050002000200129D010600143Q00202Q00060006001600122Q0007000D6Q00060002000200122Q0007000F6Q0006000600074Q0003000600024Q00010002000300124A010200173Q0020480102000200092Q00F0000300014Q00790102000200020010E73Q0017000200122Q000200083Q00202Q00020002001900104Q0018000200122Q000200083Q00202Q00020002001900104Q001A00026Q00017Q00063Q002Q033Q0049734103053Q004D6F64656C03063Q0069706169727303103Q0044524F505F4D4F44454C5F48494E545303043Q004E616D6503043Q0066696E6401183Q0020242Q013Q000100127C010300024Q00DD00010003000200064900010007000100010004603Q000700012Q006B2Q016Q005C2Q0100023Q00124A2Q0100033Q00124A010200044Q00B30001000200030004603Q0013000100204801063Q00050020240106000600062Q00F0000800054Q00DD00060008000200061E0106001300013Q0004603Q001300012Q006B010600014Q005C010600023Q0006A20001000B000100020004603Q000B00012Q006B2Q016Q005C2Q0100024Q000C012Q00017Q00093Q0003103Q006163746976655461726765744B696E6403043Q004E616D6503043Q0066696E64030F3Q00436F2Q7065725265736F7572636573030D3Q004C6561665265736F757263657303053Q0073746F6E6503093Q00462Q6F644D6F64656C030D3Q00572Q6F645265736F757263657303043Q0074722Q6501203Q0006493Q0004000100010004603Q0004000100124A2Q0100014Q005C2Q0100023Q0020482Q013Q000200202401020001000300127C010400044Q00DD0002000400020006490002000F000100010004603Q000F000100202401020001000300127C010400054Q00DD00020004000200061E0102001100013Q0004603Q0011000100127C010200064Q005C010200023Q00202401020001000300127C010400074Q00DD0002000400020006490002001B000100010004603Q001B000100202401020001000300127C010400084Q00DD00020004000200061E0102001D00013Q0004603Q001D000100127C010200094Q005C010200023Q00124A010200014Q005C010200024Q000C012Q00017Q00023Q00030C3Q0069676E6F72656444726F707303063Q00506172656E7401133Q00124A2Q0100014Q000A000100013Q00061E2Q01000600013Q0004603Q000600012Q006B2Q0100014Q005C2Q0100023Q0020482Q013Q000200061E2Q01001000013Q0004603Q0010000100124A2Q0100013Q00204801023Q00022Q000A00010001000200061E2Q01001000013Q0004603Q001000012Q006B2Q0100014Q005C2Q0100024Q006B2Q016Q005C2Q0100024Q000C012Q00017Q000B3Q00030C3Q0069676E6F72656444726F70732Q0103103Q006163746976655461726765744B696E6403063Q00506172656E742Q033Q0049734103053Q004D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C03053Q0073746F6E6503113Q0073652Q73696F6E53746F6E6544726F7073026Q00F03F03103Q0073652Q73696F6E54722Q6544726F7073011D3Q00121B000100013Q00202Q00013Q000200122Q000100033Q00202Q00023Q000400062Q0002001300013Q0004603Q0013000100204801023Q000400202401020002000500127C010400064Q00DD00020004000200061E0102001300013Q0004603Q0013000100124A010200073Q00204801033Q00042Q00790102000200022Q00F0000100023Q00124A010200013Q00204801033Q00040020370102000300020026A000010019000100080004603Q0019000100124A010200093Q00206500020002000A00128F000200093Q0004603Q001C000100124A0102000B3Q00206500020002000A00128F0002000B4Q000C012Q00017Q00063Q0003063Q00506172656E74030D3Q00697344726F7049676E6F72656403123Q006973506F73496E426C6F636B65645A6F6E6503083Q00506F736974696F6E03013Q0059026Q00244002223Q00061E012Q000500013Q0004603Q0005000100204801023Q000100064900020007000100010004603Q000700012Q006B01026Q005C010200023Q00124A010200024Q00F000036Q007901020002000200061E0102000E00013Q0004603Q000E00012Q006B01026Q005C010200023Q00124A010200033Q00204801033Q00042Q007901020002000200061E0102001500013Q0004603Q001500012Q006B01026Q005C010200023Q00061E2Q01001F00013Q0004603Q001F000100204801023Q00040020480102000200050020480103000100052Q0048000200020003000EA70106001F000100020004603Q001F00012Q006B01026Q005C010200024Q006B010200014Q005C010200024Q000C012Q00017Q00183Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403063Q0043616D657261030F3Q00707573684661726D5761726E696E6703093Q006E6F5F63616D657261032A3Q00D09DD0B5D1822043616D65726120E2809420D0BBD183D18220D0BDD0B520D0BDD0B0D0B9D0B4D0B5D0BD03103Q00636C6561724661726D5761726E696E6703063Q00697061697273030B3Q004765744368696C6472656E03133Q0069735265736F7572636544726F704D6F64656C03063Q00506172656E74030E3Q00676574436F2Q6C6563745061727403123Q00697356616C6964436F2Q6C65637444726F7003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030E3Q00434F2Q4C4543545F52414449555303053Q007461626C6503063Q00696E7365727403043Q00736F727401464Q00702Q015Q0006493Q0004000100010004603Q000400012Q005C2Q0100023Q00124A010200013Q00202401020002000200127C010400034Q00DD0002000400020006490002000F000100010004603Q000F000100124A010300043Q00127C010400053Q00127C010500064Q00680103000500012Q005C2Q0100023Q00124A010300073Q001238010400056Q00030002000100122Q000300083Q00202Q0004000200094Q000400056Q00033Q000500044Q003C000100124A0108000A4Q00F0000900074Q007901080002000200061E0108003C00013Q0004603Q003C000100204801080007000B00061E0108003C00013Q0004603Q003C000100124A0108000C4Q00F0000900074Q007901080002000200061E0108003C00013Q0004603Q003C000100124A0109000D4Q00F0000A00084Q00F0000B6Q00DD0009000B000200061E0109003C00013Q0004603Q003C000100124A0109000E3Q00207A01090009000F00202Q000A0008001000202Q000A000A001100202Q000B3Q001200202Q000C0008001000202Q000C000C00134Q0009000C00024Q000900093Q00202Q00090009001400122Q000A00153Q00062Q0009003C0001000A0004603Q003C000100124A010A00163Q002048010A000A00172Q00F0000B00014Q00F0000C00084Q0068010A000C00010006A200030017000100020004603Q0017000100124A010300163Q0020480103000300182Q00F0000400013Q00068800053Q000100012Q00F08Q00680103000500012Q005C2Q0100024Q000C012Q00013Q00013Q00073Q0003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465021E3Q00124A010200013Q00204801020002000200204801033Q00030020480103000300042Q009601045Q00204801040004000500204801053Q00030020480105000500062Q00DD0002000500022Q009601036Q00480002000200030020DA00020002000700122Q000300013Q00202Q00030003000200202Q00040001000300202Q0004000400044Q00055Q00202Q00050005000500202Q00060001000300202Q0006000600064Q0003000600022Q009601046Q00480003000300040020480103000300070006230002001B000100030004603Q001B00012Q007100046Q006B010400014Q005C010400024Q000C012Q00017Q00023Q00030D3Q006765744E6F646543656E74657203173Q0066696E6443616D6572615265736F7572636544726F7073010C3Q00124A2Q0100014Q00F000026Q00792Q010002000200064900010007000100010004603Q000700012Q007001026Q005C010200023Q00124A010200024Q00F0000300014Q0051010200034Q00C700026Q000C012Q00017Q00073Q0003113Q006D61726B44726F70436F2Q6C656374656403163Q0046696E6446697273744368696C645768696368497341030F3Q0050726F78696D69747950726F6D707403063Q00506172656E7403053Q007063612Q6C030C3Q0073686F756C645072652Q734603063Q007072652Q734601223Q0006493Q0003000100010004603Q000300012Q000C012Q00013Q00124A2Q0100014Q000300028Q00010002000100202Q00013Q000200122Q000300036Q000400016Q00010004000200062Q00010015000100010004603Q0015000100204801023Q000400061E0102001500013Q0004603Q0015000100204801023Q000400209801020002000200122Q000400036Q000500016Q0002000500024Q000100023Q00061E2Q01001B00013Q0004603Q001B000100124A010200053Q00068800033Q000100012Q00F03Q00014Q00E300020002000100124A010200064Q00B500020001000200061E0102002100013Q0004603Q0021000100124A010200074Q00280102000100012Q000C012Q00013Q00013Q00013Q0003133Q006669726570726F78696D69747970726F6D707400043Q00124A012Q00014Q00962Q016Q00E33Q000200012Q000C012Q00017Q00163Q0003093Q006661726D506861736503073Q00636F2Q6C656374030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E7454617267657450617274030D3Q006765744E6F646543656E746572030C3Q0069676E6F72656444726F7073026Q00F03F026Q00344003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E65617203063Q0069706169727303123Q00697356616C6964436F2Q6C65637444726F7003083Q00506F736974696F6E030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C6557616974027B14AE47E17AB43F030B3Q00636F2Q6C65637450617274029A5Q99A93F029A5Q99B93F03133Q0073746F704368617261637465724D6F74696F6E02593Q00120D010200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200076Q00036Q00790102000200022Q007001035Q00128F000300083Q00127C010300093Q00127C0104000A3Q00127C010500093Q00048A00030054000100124A0107000B4Q00F0000800014Q007901070002000200064900070017000100010004603Q001700010004603Q0054000100124A0107000C4Q00F000086Q00790107000200022Q0019000800073Q0026A00008001E000100040004603Q001E00010004603Q0054000100124A0108000D4Q00F0000900074Q00B300080002000A0004603Q004A000100124A010D000B4Q00F0000E00014Q0079010D00020002000649000D0028000100010004603Q002800010004603Q004A000100124A010D000E4Q00F0000E000C4Q00F0000F00024Q00DD000D000F0002000649000D002F000100010004603Q002F00010004603Q004A0001002048010D000C000F00124A010E00104Q00F0000F000D4Q00E3000E0002000100128F000C00063Q00124A010E00113Q00127C010F00124Q00F0001000014Q00DD000E00100002000649000E003B000100010004603Q003B00010004603Q004A000100124A010E00104Q0002000F000D6Q000E0002000100122Q000E00136Q000F000C6Q000E0002000100122Q000E00113Q00122Q000F00146Q001000016Q000E0010000200062Q000E0048000100010004603Q004800010004603Q004A00012Q0091000E000E3Q00128F000E00063Q0006A200080022000100020004603Q0022000100124A010800113Q00127C010900154Q00F0000A00014Q00DD0008000A000200064900080053000100010004603Q005300010004603Q0054000100047E0103001100012Q0091000300033Q00128F000300063Q00124A010300164Q00280103000100012Q000C012Q00017Q000A3Q00030B3Q00412Q7461636B44656C6179028Q0003043Q007469636B030C3Q006C617374412Q7461636B417403063Q007072652Q7346030F3Q0067657441696D5363722Q656E506F7303083Q00557365436C69636B03073Q00636C69636B417403113Q004C656769744D6F75736543617074757265030B3Q00686F6C644D6F7573654174012B3Q0006493Q0003000100010004603Q000300012Q000C012Q00013Q00124A2Q0100013Q000EA70102000E000100010004603Q000E000100124A2Q0100034Q005E2Q010001000200122Q000200046Q00010001000200122Q000200013Q00062Q0001000E000100020004603Q000E00012Q000C012Q00013Q00124A2Q0100034Q008300010001000200122Q000100043Q00122Q000100056Q00010001000100122Q000100066Q00028Q00010002000200062Q0001001A00013Q0004603Q001A00010006490002001B000100010004603Q001B00012Q000C012Q00013Q00124A010300073Q00061E0103002300013Q0004603Q0023000100124A010300084Q00F0000400014Q00F0000500024Q00680103000500010004603Q002A000100124A010300093Q00061E0103002A00013Q0004603Q002A000100124A0103000A4Q00F0000400014Q00F0000500024Q00680103000500012Q000C012Q00017Q00043Q0003063Q0069706169727303163Q00412Q73656D626C794C696E65617256656C6F6369747903093Q004D61676E6974756465026Q00F83F010F3Q00124A2Q0100014Q00F000026Q00B30001000200030004603Q000A0001002048010600050002002048010600060003000EA70104000A000100060004603Q000A00012Q006B01066Q005C010600023Q0006A200010004000100020004603Q000400012Q006B2Q0100014Q005C2Q0100024Q000C012Q00017Q000F3Q0003093Q006661726D506861736503043Q0077616974030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403113Q00696E74652Q7275707469626C6557616974026Q00D03F03043Q007469636B026Q00084003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E656172030F3Q0064726F707341726553652Q746C6564026Q00F03F029A5Q99B93F023E3Q0012AD000200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200073Q00122Q000300084Q00F0000400014Q00DD00020004000200064900020010000100010004603Q001000012Q007001026Q005C010200023Q00124A010200094Q00B500020001000200206500020002000A00124A0103000B4Q00F0000400014Q007901030002000200061E0103003900013Q0004603Q0039000100124A010300094Q00B500030001000200061701030039000100020004603Q0039000100124A0103000C4Q00F000046Q00790103000200022Q0019000400033Q000EA701040029000100040004603Q0029000100124A0104000D4Q00F0000500034Q007901040002000200061E0104003000013Q0004603Q003000012Q005C010300023Q0004603Q0030000100124A010400094Q00B500040001000200208001050002000E00061701050030000100040004603Q003000012Q007001046Q005C010400023Q00124A010400073Q00127C0105000F4Q00F0000600014Q00DD00040006000200064900040013000100010004603Q001300012Q007001046Q005C010400023Q0004603Q0013000100124A0103000C4Q00F000046Q0051010300044Q00C700036Q000C012Q00017Q00023Q0003053Q0073746F6E65030D3Q006765744E6F646543656E746572030C3Q0026A00001000A000100010004603Q000A000100061E012Q000A00013Q0004603Q000A000100124A010300024Q00F000046Q007901030002000200061E0103000A00013Q0004603Q000A00012Q005C010300024Q005C010200024Q000C012Q00017Q00263Q0003093Q006661726D506861736503043Q006D696E6503113Q0063752Q72656E745461726765745061727403063Q00506172656E7403063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030F3Q0067657450617274506F736974696F6E03103Q006765744D696E65416E63686F72506F73030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403183Q0067657454656C65706F7274486569676874466F724B696E6403013Q0059030C3Q004F72626974456E61626C6564030A3Q006F72626974416E676C65030A3Q004F7262697453702Q6564026Q11913F030D3Q004F726269744469616D65746572027Q004003073Q00566563746F72332Q033Q006E657703013Q005803043Q006D6174682Q033Q00636F7303013Q005A2Q033Q0073696E030B3Q0041696D417454617267657403153Q00612Q706C79487270434672616D65496E7374616E7403063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747903113Q004C656769744D6F75736543617074757265030F3Q0067657441696D5363722Q656E506F7303083Q00557365436C69636B030B3Q00686F6C644D6F757365417403113Q006D6F76654D6F757365546F5363722Q656E00863Q00124A012Q00013Q0026CD3Q0004000100020004603Q000400012Q000C012Q00013Q00124A012Q00033Q00061E012Q000B00013Q0004603Q000B000100124A012Q00033Q002048014Q00040006493Q000C000100010004603Q000C00012Q000C012Q00013Q00124A012Q00053Q002048014Q000600061E012Q001500013Q0004603Q0015000100124A012Q00053Q002048014Q0006002024014Q000700127C010200084Q00DD3Q000200020006493Q0018000100010004603Q001800012Q000C012Q00013Q00124A2Q0100093Q00124A010200034Q00792Q01000200020006490001001E000100010004603Q001E00012Q000C012Q00013Q00124A0102000A3Q0012C80003000B3Q00122Q0004000C6Q000500016Q00020005000200122Q0003000D3Q00122Q0004000C6Q00030002000200202Q00040002000E4Q0004000400034Q000500053Q00122Q0006000F3Q00062Q0006004700013Q0004603Q0047000100124A010600103Q001282000700113Q00202Q0007000700124Q00060006000700122Q000600103Q00122Q000600133Q00202Q00060006001400122Q000700153Q00202Q00070007001600202Q00080002001700122Q000900183Q00202Q00090009001900122Q000A00106Q0009000200024Q0009000900064Q0008000800094Q000900043Q00202Q000A0002001A00122Q000B00183Q00202Q000B000B001B00122Q000C00106Q000B000200024Q000B000B00064Q000A000A000B4Q0007000A00024Q000500073Q00044Q004E000100124A010600153Q00206C00060006001600202Q0007000200174Q000800043Q00202Q00090002001A4Q0006000900024Q000500063Q00124A0106001C3Q00061E0106005C00013Q0004603Q005C000100061E2Q01005C00013Q0004603Q005C000100124A0106001D4Q008C01075Q00122Q0008001E3Q00202Q0008000800164Q000900056Q000A00016Q0008000A6Q00063Q000100044Q0063000100124A0106001D4Q00B100075Q00122Q0008001E3Q00202Q0008000800164Q000900056Q000800096Q00063Q000100124A010600153Q00203000060006002000104Q001F000600122Q000600153Q00202Q00060006002000104Q0021000600122Q000600223Q00062Q0006008500013Q0004603Q0085000100124A010600033Q00061E0106008500013Q0004603Q0085000100124A010600233Q00124A010700034Q00B300060002000700061E0106008500013Q0004603Q0085000100061E0107008500013Q0004603Q0085000100124A010800243Q0006490008007E000100010004603Q007E000100124A010800254Q00F0000900064Q00F0000A00074Q00680108000A00010004603Q0085000100124A0108001C3Q00061E0108008500013Q0004603Q0085000100124A010800264Q00F0000900064Q00F0000A00074Q00680108000A00012Q000C012Q00017Q00063Q00030C3Q00476574412Q7472696275746503123Q004D617869487562426C61636B5363722Q656E2Q01030E3Q00626C61636B5363722Q656E477569030C3Q007363722Q656E477569526566030E3Q00497344657363656E64616E744F6601213Q0006493Q0004000100010004603Q000400012Q006B2Q016Q005C2Q0100023Q0020242Q013Q000100127C010300024Q00DD0001000300020026A00001000B000100030004603Q000B00012Q006B2Q0100014Q005C2Q0100023Q00124A2Q0100043Q00061E2Q01001300013Q0004603Q0013000100124A2Q0100043Q00069C3Q0013000100010004603Q001300012Q006B2Q0100014Q005C2Q0100023Q00124A2Q0100053Q00061E2Q01001F00013Q0004603Q001F000100124A2Q0100053Q0006A4012Q001E000100010004603Q001E00010020242Q013Q000600124A010300054Q00DD0001000300020004603Q001F00012Q007100016Q006B2Q0100014Q005C2Q0100024Q000C012Q00017Q00073Q0003063Q00737472696E6703053Q006C6F77657203043Q004E616D6503063Q00697061697273030B3Q0054524144455F48494E545303043Q0066696E64026Q00F03F01183Q00124A2Q0100013Q0020482Q010001000200204801023Q00032Q00792Q010002000200124A010200043Q00124A010300054Q00B30002000200040004603Q0013000100124A010700013Q00205F0107000700064Q000800016Q000900063Q00122Q000A00076Q000B00016Q0007000B000200062Q0007001300013Q0004603Q001300012Q006B010700014Q005C010700023Q0006A200020008000100020004603Q000800012Q006B01026Q005C010200024Q000C012Q00017Q00083Q0003083Q0069734F75724775692Q033Q0049734103093Q005363722Q656E47756903073Q00456E61626C6564010003093Q004775694F626A65637403073Q0056697369626C6503063Q0041637469766501153Q00124A2Q0100014Q00F000026Q00792Q010002000200061E2Q01000600013Q0004603Q000600012Q000C012Q00013Q0020242Q013Q000200127C010300034Q00DD00010003000200061E2Q01000D00013Q0004603Q000D000100309F012Q000400050004603Q001400010020242Q013Q000200127C010300064Q00DD00010003000200061E2Q01001400013Q0004603Q0014000100309F012Q0007000500309F012Q000800052Q000C012Q00017Q00053Q00030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A65637403063Q00697061697273030E3Q0047657444657363656E64616E7473011E3Q00124A2Q0100013Q00061E2Q01000500013Q0004603Q000500010006493Q0006000100010004603Q000600012Q000C012Q00013Q00124A2Q0100024Q00F000026Q00792Q010002000200061E2Q01000E00013Q0004603Q000E000100124A2Q0100034Q00F000026Q00E300010002000100124A2Q0100043Q00202401023Q00052Q00FA000200034Q001800013Q00030004603Q001B000100124A010600024Q00F0000700054Q007901060002000200061E0106001B00013Q0004603Q001B000100124A010600034Q00F0000700054Q00E30006000200010006A200010013000100020004603Q001300012Q000C012Q00017Q000B3Q0003113Q00426C6F636B5569447572696E674661726D03063Q0069706169727303093Q00706C61796572477569030B3Q004765744368696C6472656E2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F757247756903073Q00456E61626C6564030A3Q0068692Q64656E477569733Q012Q001D3Q00124A012Q00013Q0006493Q0004000100010004603Q000400012Q000C012Q00013Q00124A012Q00023Q001256000100033Q00202Q0001000100044Q000100029Q00000200044Q001A000100202401050004000500127C010700064Q00DD00050007000200061E0105001A00013Q0004603Q001A000100124A010500074Q00F0000600044Q00790105000200020006490005001A000100010004603Q001A000100204801050004000800061E0105001A00013Q0004603Q001A000100124A010500093Q00203701050004000A00309F01040008000B0006A23Q000A000100020004603Q000A00012Q000C012Q00017Q00023Q0003053Q0070616972730001083Q00124A2Q0100014Q00F000026Q00B30001000200030004603Q00050001002037012Q000400020006A200010004000100010004603Q000400012Q000C012Q00017Q000A3Q0003053Q00706169727303133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q007063612Q6C030A3Q00636C6561725461626C65030A3Q0068692Q64656E4775697303063Q00506172656E742Q0103043Q006E65787403043Q007461736B03053Q006465666572002B3Q00124A012Q00013Q00124A2Q0100024Q00B33Q000200020004603Q000B000100061E0104000A00013Q0004603Q000A000100124A010500033Q00068800063Q000100012Q00F03Q00044Q00E30005000200012Q002D01035Q0006A23Q0004000100020004603Q0004000100124A012Q00043Q00125D2Q0100028Q000200019Q0000122Q000100013Q00122Q000200056Q00010002000300044Q001B000100204801060004000600061E0106001B00013Q0004603Q001B000100061E0105001B00013Q0004603Q001B0001002037012Q000400070006A200010015000100020004603Q0015000100124A2Q0100043Q00124A010200054Q00E300010002000100124A2Q0100084Q00F000026Q00792Q010002000200061E2Q01002A00013Q0004603Q002A000100124A2Q0100093Q0020482Q010001000A00068800020001000100012Q00F08Q00E30001000200012Q000C012Q00013Q00023Q00013Q00030A3Q00446973636F2Q6E65637400044Q0096016Q002024014Q00012Q00E33Q000200012Q000C012Q00017Q00043Q0003053Q00706169727303063Q00506172656E7403073Q00456E61626C65642Q01000B3Q00124A012Q00014Q00962Q016Q00B33Q000200020004603Q0008000100204801040003000200061E0104000800013Q0004603Q0008000100309F0103000300040006A23Q0004000100010004603Q000400012Q000C012Q00017Q000B3Q00030C3Q0073746F70536166654D6F6465030D3Q00686964654F746865724775697303043Q007461736B03053Q00646566657203133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q006368696C6403093Q00706C61796572477569030A3Q004368696C64412Q64656403073Q00436F2Q6E65637403043Q0064657363030F3Q0044657363656E64616E74412Q64656400173Q00127E3Q00018Q0001000100124Q00028Q0001000100124Q00033Q00206Q00040002352Q016Q00C23Q0002000100124Q00053Q00122Q000100073Q00202Q00010001000800202Q000100010009000235010300014Q004D00010003000200104Q0006000100124Q00053Q00122Q000100073Q00202Q00010001000B00202Q000100010009000235010300024Q00DD000100030002001032012Q000A00012Q000C012Q00013Q00033Q00033Q00030B3Q004661726D456E61626C6564030A3Q007363616E54726164657303093Q00706C6179657247756900073Q00124A012Q00013Q00061E012Q000600013Q0004603Q0006000100124A012Q00023Q00124A2Q0100034Q00E33Q000200012Q000C012Q00017Q00033Q00030B3Q004661726D456E61626C656403043Q007461736B03053Q006465666572010A3Q00124A2Q0100013Q00064900010004000100010004603Q000400012Q000C012Q00013Q00124A2Q0100023Q0020482Q010001000300068800023Q000100012Q00F08Q00E30001000200012Q000C012Q00013Q00013Q00093Q0003113Q00426C6F636B5569447572696E674661726D2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F7572477569030A3Q0068692Q64656E477569732Q0103073Q00456E61626C65640100030A3Q007363616E54726164657300173Q00124A012Q00013Q00061E012Q001300013Q0004603Q001300012Q0096016Q002024014Q000200127C010200034Q00DD3Q0002000200061E012Q001300013Q0004603Q0013000100124A012Q00044Q00962Q016Q0079012Q000200020006493Q0013000100010004603Q0013000100124A012Q00054Q00962Q015Q002037012Q000100062Q0096016Q00309F012Q0007000800124A012Q00094Q00962Q016Q00E33Q000200012Q000C012Q00017Q00053Q00030B3Q004661726D456E61626C6564030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B65547261646503043Q007461736B03053Q00646566657201123Q00124A2Q0100013Q00061E2Q01000600013Q0004603Q0006000100124A2Q0100023Q00064900010007000100010004603Q000700012Q000C012Q00013Q00124A2Q0100034Q00F000026Q00792Q010002000200061E2Q01001100013Q0004603Q0011000100124A2Q0100043Q0020482Q010001000500068800023Q000100012Q00F08Q00E30001000200012Q000C012Q00013Q00013Q00013Q00030F3Q006869646554726164654F626A65637400043Q00124A012Q00014Q00962Q016Q00E33Q000200012Q000C012Q00017Q00043Q0003063Q00706C61796572030E3Q0046696E6446697273744368696C6403043Q004461746103093Q005265736F7572636573000D3Q00123A3Q00013Q00206Q000200122Q000200038Q0002000200064Q0008000100010004603Q000800012Q0091000100014Q005C2Q0100023Q0020242Q013Q000200127C010300044Q00512Q0100034Q00C700016Q000C012Q00017Q00073Q0003123Q006765745265736F7572636573466F6C646572028Q00030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565011A3Q00124A2Q0100014Q00B500010001000200064900010006000100010004603Q0006000100127C010200024Q005C010200023Q0020240102000100032Q00F000046Q00DD00020004000200061E0102001700013Q0004603Q0017000100202401030002000400127C010500054Q00DD00030005000200064900030015000100010004603Q0015000100202401030002000400127C010500064Q00DD00030005000200061E0103001700013Q0004603Q001700010020480103000200072Q005C010300023Q00127C010300024Q005C010300024Q000C012Q00017Q00053Q00028Q0003073Q00436F636F6E757403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7400133Q00127C012Q00013Q00127C2Q0100023Q00124A010200033Q00124A010300044Q00B30002000200040004603Q000D000100124A010700054Q00F0000800064Q0079010700020002000617012Q000D000100070004603Q000D00012Q00F03Q00074Q00F0000100063Q0006A200020006000100020004603Q000600012Q00F000026Q00F0000300014Q001D000200034Q000C012Q00017Q00053Q00030F3Q004175746F53652Q6C456E61626C656403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7403143Q0053652Q6C436F636F6E75745468726573686F6C6400163Q00124A012Q00013Q0006493Q0005000100010004603Q000500012Q006B017Q005C012Q00023Q00124A012Q00023Q00124A2Q0100034Q00B33Q000200020004603Q0011000100124A010500044Q00F0000600044Q007901050002000200124A010600053Q00061701060011000100050004603Q001100012Q006B010500014Q005C010500023Q0006A23Q0009000100020004603Q000900012Q006B017Q005C012Q00024Q000C012Q00017Q00073Q00030D3Q006661726D54696D65546F74616C030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q0003043Q007469636B03043Q006D61746803053Q00666C2Q6F7200123Q00124A012Q00013Q00124A2Q0100023Q00061E2Q01000C00013Q0004603Q000C000100124A2Q0100033Q000EA70104000C000100010004603Q000C000100124A2Q0100054Q00B500010001000200124A010200034Q00480001000100022Q004E014Q000100124A2Q0100063Q00208E2Q01000100074Q00028Q000100026Q00019Q0000017Q00073Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E2Q033Q0073796E03043Q00682Q7470030B3Q00482Q747053657276696365030C3Q00526571756573744173796E63013A3Q0002352Q015Q00124A010200013Q00124A010300024Q00790102000200020026A00002000D000100030004603Q000D00012Q00F0000200013Q00068800030001000100012Q00F08Q007901020002000200061E0102000D00013Q0004603Q000D00012Q005C010200023Q00124A010200043Q00061E0102001B00013Q0004603Q001B000100124A010200043Q00204801020002000200061E0102001B00013Q0004603Q001B00012Q00F0000200013Q00068800030002000100012Q00F08Q007901020002000200061E0102001B00013Q0004603Q001B00012Q005C010200023Q00124A010200053Q00061E0102002900013Q0004603Q0029000100124A010200053Q00204801020002000200061E0102002900013Q0004603Q002900012Q00F0000200013Q00068800030003000100012Q00F08Q007901020002000200061E0102002900013Q0004603Q002900012Q005C010200023Q00124A010200063Q00061E0102003700013Q0004603Q0037000100124A010200063Q00204801020002000700061E0102003700013Q0004603Q003700012Q00F0000200013Q00068800030004000100012Q00F08Q007901020002000200061E0102003700013Q0004603Q003700012Q005C010200024Q0091000200024Q005C010200024Q000C012Q00013Q00053Q00013Q0003053Q007063612Q6C01093Q00124A2Q0100014Q00F000026Q00B300010002000200061E2Q01000600013Q0004603Q000600012Q005C010200024Q0091000300034Q005C010300024Q000C012Q00017Q00013Q0003073Q007265717565737400053Q00127F3Q00016Q00019Q0000019Q008Q00017Q00023Q002Q033Q0073796E03073Q007265717565737400063Q0012073Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00023Q0003043Q00682Q747003073Q007265717565737400063Q0012073Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00073Q00030B3Q00482Q747053657276696365030C3Q00526571756573744173796E632Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q004865616465727303043Q00426F647900153Q001287012Q00013Q00206Q00024Q00023Q00044Q00035Q00202Q00030003000300102Q0002000300034Q00035Q00202Q00030003000400062Q0003000B000100010004603Q000B000100127C010300053Q0010320102000400032Q007101035Q00202Q00030003000600102Q0002000600034Q00035Q00202Q00030003000700102Q0002000700036Q00029Q008Q00017Q001F3Q0003043Q006773756203043Q005E25732B034Q0003043Q0025732B2403143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B9030B3Q00682Q7470526571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030A3Q00537461747573436F646503063Q0073746174757303063Q0053746174757303083Q00746F6E756D626572026Q006940025Q00C0724003143Q00D09ED182D0BFD180D0B0D0B2D0BBD0B5D0BDD0BE03053Q00482Q54502003083Q00746F737472696E6703073Q0053752Q63652Q733Q010003113Q00482Q545020D0BED188D0B8D0B1D0BAD0B003053Q007063612Q6C031D3Q00D09ED188D0B8D0B1D0BAD0B020D0BED182D0BFD180D0B0D0B2D0BAD0B82Q033Q00737562026Q00F03F026Q005840025D3Q00206D01023Q000100122Q000400023Q00122Q000500036Q00020005000200202Q00020002000100122Q000400043Q00122Q000500036Q0002000500026Q00023Q00264Q000E000100030004603Q000E00012Q006B01025Q00127C010300054Q001D000200033Q00124A010200064Q00D200033Q000400102Q000300073Q00302Q0003000800094Q00043Q000100302Q0004000B000C00102Q0003000A000400102Q0003000D00014Q00020002000200062Q0002004700013Q0004603Q0047000100204801030002000E00064900030020000100010004603Q0020000100204801030002000F00064900030020000100010004603Q0020000100204801030002001000061E0103003800013Q0004603Q0038000100124A010400114Q00F0000500034Q007901040002000200061E0104003800013Q0004603Q0038000100124A010400114Q00F0000500034Q0079010400020002000E6700120031000100040004603Q0031000100263E00040031000100130004603Q003100012Q006B010500013Q00127C010600144Q001D000500034Q006B01055Q001213010600153Q00122Q000700166Q000800036Q0007000200024Q0006000600074Q000500033Q0020480104000200170026A00004003E000100180004603Q003E00012Q006B010400013Q00127C010500144Q001D000400033Q0020480104000200170026A000040044000100190004603Q004400012Q006B01045Q00127C0105001A4Q001D000400034Q006B010400013Q00127C010500144Q001D000400033Q00124A0103001B3Q00068800043Q000100022Q00F08Q00F03Q00014Q00B300030002000400061E0103005100013Q0004603Q005100012Q006B010500013Q00127C010600144Q001D000500034Q006B01055Q00124A010600163Q0006A001070056000100040004603Q0056000100127C0107001C4Q007901060002000200202D00060006001D00122Q0008001E3Q00122Q0009001F6Q000600096Q00059Q0000013Q00013Q00053Q00030B3Q00482Q74705365727669636503093Q00506F73744173796E6303043Q00456E756D030F3Q00482Q7470436F6E74656E7454797065030F3Q00412Q706C69636174696F6E4A736F6E000A3Q001231012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400033Q00202Q00040004000400202Q0004000400054Q00059Q00000500016Q00017Q001F3Q00034Q0003143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B903043Q006E616D65030A3Q00D098D0B3D180D0BED0BA03053Q0076616C756503063Q00706C6179657203043Q004E616D652Q033Q0020286003083Q00746F737472696E6703063Q0055736572496403023Q00602903063Q00696E6C696E65010003063Q0069706169727303053Q007461626C6503063Q00696E73657274030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646503063Q00656D6265647303053Q007469746C6503053Q00636F6C6F72023Q00806D4C4A4103063Q006669656C647303063Q00662Q6F74657203043Q007465787403083Q004D4158492048554203093Q0074696D657374616D7003083Q004461746554696D652Q033Q006E6F7703093Q00546F49736F4461746503123Q00706F7374446973636F7264576562682Q6F6B04403Q00061E012Q000400013Q0004603Q000400010026A03Q0007000100010004603Q000700012Q006B01045Q00127C010500024Q001D000400034Q0070010400014Q007001053Q000300309F01050003000400124A010600063Q00204801060006000700127C010700083Q00124A010800093Q00124A010900063Q00204801090009000A2Q007901080002000200127C0109000B4Q000B01060006000900103201050005000600309F0105000C000D2Q003601040001000100061E0103002300013Q0004603Q0023000100124A0105000E4Q00F0000600034Q00B30005000200070004603Q0021000100124A010A000F3Q002048010A000A00102Q00F0000B00044Q00F0000C00094Q0068010A000C00010006A20005001C000100020004603Q001C000100124A010500113Q0020240105000500122Q007001073Q00012Q0070010800014Q007001093Q00050010320109001400010006A0010A002C000100020004603Q002C000100127C010A00163Q00103201090015000A0010440109001700044Q000A3Q000100302Q000A0019001A00102Q00090018000A00122Q000A001C3Q00202Q000A000A001D4Q000A0001000200202Q000A000A001E4Q000A0002000200102Q0009001B000A4Q0008000100010010320107001300082Q009900050007000200122Q0006001F6Q00078Q000800056Q000600086Q00069Q0000017Q00193Q0003123Q006765745265736F7572636573466F6C6465722Q033Q00E2809403063Q00697061697273030B3Q004765744368696C6472656E2Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565026Q00F03F03053Q007461626C6503063Q00696E7365727403043Q006E616D6503043Q004E616D652Q033Q0076616C03043Q00736F727403023Q003A2003083Q00746F737472696E6703063Q00636F6E63617403013Q000A025Q00408F4003063Q00737472696E672Q033Q00737562025Q00288F402Q033Q003Q2E029Q00523Q00124A012Q00014Q00B53Q000100020006493Q0006000100010004603Q0006000100127C2Q0100024Q005C2Q0100024Q00702Q015Q001256000200033Q00202Q00033Q00044Q000300046Q00023Q000400044Q0022000100202401070006000500127C010900064Q00DD00070009000200064900070016000100010004603Q0016000100202401070006000500127C010900074Q00DD00070009000200061E0107002200013Q0004603Q00220001002048010700060008000EA701090022000100070004603Q0022000100124A0107000A3Q00203500070007000B4Q000800016Q00093Q000200202Q000A0006000D00102Q0009000C000A00202Q000A0006000800102Q0009000E000A4Q0007000900010006A20002000C000100020004603Q000C000100124A0102000A3Q00204801020002000F2Q00F0000300013Q00023501046Q00680102000400012Q007001025Q00124A010300034Q00F0000400014Q00B30003000200050004603Q0038000100124A0108000A3Q0020A100080008000B4Q000900023Q00202Q000A0007000C00122Q000B00103Q00122Q000C00113Q00202Q000D0007000E4Q000C000200024Q000A000A000C4Q0008000A00010006A20003002E000100020004603Q002E000100124A0103000A3Q00202B0103000300124Q000400023Q00122Q000500136Q0003000500024Q000400033Q000E2Q0014004A000100040004603Q004A000100124A010400153Q0020460004000400164Q000500033Q00122Q000600093Q00122Q000700176Q00040007000200122Q000500186Q0003000400052Q0019000400023Q000EA70119004F000100040004603Q004F00010006A001040050000100030004603Q0050000100127C010400024Q005C010400024Q000C012Q00013Q00013Q00013Q002Q033Q0076616C02083Q00204801023Q000100204801030001000100062300030005000100020004603Q000500012Q007100026Q006B010200014Q005C010200024Q000C012Q00017Q001C3Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D617403093Q002564D0BC202564D18103023Q00D18103043Q006E616D65031D3Q00D0A1D180D183D0B1D0B8D0BB20D0B4D0B5D180D0B5D0B2D18CD0B5D0B203053Q0076616C756503083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q00696E6C696E652Q0103193Q00D0A1D180D183D0B1D0B8D0BB20D0BAD0B0D0BCD0BDD0B5D0B903123Q0073652Q73696F6E53746F6E65734D696E6564031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0B4D0B5D1802E2903103Q0073652Q73696F6E54722Q6544726F7073031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0BAD0B0D0BC2E2903113Q0073652Q73696F6E53746F6E6544726F707303153Q00D092D180D0B5D0BCD18F20D184D0B0D180D0BCD0B0030A3Q00D0A0D0B5D0B6D0B8D0BC030F3Q006765744661726D4D6F646554657874030E3Q005265736F757263657320283E312903173Q006765745265736F75726365734F7665724F6E6554657874012Q00453Q00124A012Q00014Q00B53Q0001000200124A2Q0100023Q0020482Q010001000300202400023Q00042Q00792Q010002000200201C00023Q00042Q0091000300033Q000EA701050012000100010004603Q0012000100124A010400063Q00202A01040004000700122Q000500086Q000600016Q000700026Q0004000700024Q000300043Q00044Q001500012Q00F000045Q00127C010500094Q000B0103000400052Q0070010400074Q007001053Q000300309F0105000A000B00124A0106000D3Q00124A0107000E4Q007801060002000200102Q0005000C000600302Q0005000F00104Q00063Q000300302Q0006000A001100122Q0007000D3Q00122Q000800126Q00070002000200102Q0006000C000700302Q0006000F00102Q007001073Q000300309F0107000A001300124A0108000D3Q00124A010900144Q007801080002000200102Q0007000C000800302Q0007000F00104Q00083Q000300302Q0008000A001500122Q0009000D3Q00122Q000A00166Q00090002000200102Q0008000C000900302Q0008000F00102Q007001093Q000300309F0109000A00170010320109000C000300309F0109000F00102Q0070010A3Q000300302E000A000A001800122Q000B00196Q000B0001000200102Q000A000C000B00302Q000A000F00104Q000B3Q000300302Q000B000A001A00122Q000C001B6Q000C0001000200102Q000B000C000C00309F010B000F001C2Q00360104000700012Q005C010400024Q000C012Q00017Q00083Q0003153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003063Q0069706169727303153Q0067657453652Q73696F6E53746174734669656C647303053Q007461626C6503063Q00696E7365727403103Q0073656E64446973636F7264456D626564021F3Q00124A010200013Q00064900020004000100010004603Q000400012Q000C012Q00013Q00124A010200024Q00B500020001000200061E0102000A00013Q0004603Q000A00010026A00002000B000100030004603Q000B00012Q000C012Q00014Q007001035Q001261010400043Q00122Q000500056Q000500016Q00043Q000600044Q0016000100124A010900063Q0020480109000900072Q00F0000A00034Q00F0000B00084Q00680109000B00010006A200040011000100020004603Q0011000100124A010400084Q005F000500026Q00068Q000700016Q000800036Q0004000800016Q00017Q00093Q0003043Q007469636B026Q00284003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403043Q007461736B03043Q0077616974029A5Q99B93F011C3Q00124A2Q0100014Q00B50001000100020006A00102000500013Q0004603Q0005000100127C010200024Q004E2Q010001000200124A010200014Q00B500020001000200061701020019000100010004603Q0019000100124A010200033Q00204801020002000400063200030011000100020004603Q0011000100202401030002000500127C010500064Q00DD00030005000200061E0103001400013Q0004603Q001400012Q005C010300023Q00124A010400073Q00204801040004000800127C010500094Q00E30004000200010004603Q000600012Q0091000200024Q005C010200024Q000C012Q00017Q00053Q0003053Q00666F72636503043Q007461736B03043Q007761697403113Q00696E74652Q7275707469626C655761697403053Q0072756E496402133Q00061E2Q01000B00013Q0004603Q000B000100204801020001000100061E0102000B00013Q0004603Q000B000100124A010200023Q00202F0102000200034Q00038Q0002000200014Q000200016Q000200023Q00124A010200044Q00F000035Q00063200040010000100010004603Q001000010020480104000100052Q0051010200044Q00C700026Q000C012Q00017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E40030E3Q0053652Q6C4974656D52656D6F7465000F3Q0012A73Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q0009000100010004603Q000900012Q0091000100014Q005C2Q0100023Q0020242Q013Q0002001245000300053Q00122Q000400046Q000100046Q00019Q0000017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E4003133Q00576F726C6454656C65706F727452656D6F7465000F3Q0012A73Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q0009000100010004603Q000900012Q0091000100014Q005C2Q0100023Q0020242Q013Q0002001245000300053Q00122Q000400046Q000100046Q00019Q0000017Q00023Q0003163Q00676574576F726C6454656C65706F727452656D6F746503053Q007063612Q6C010D3Q00124A2Q0100014Q00B500010001000200064900010006000100010004603Q000600012Q006B01026Q005C010200023Q00124A010200023Q00068800033Q000100022Q00F08Q00F03Q00014Q00790102000200022Q005C010200024Q000C012Q00013Q00013Q00053Q00026Q00F03F027Q0040030C3Q00496E766F6B6553657276657203053Q007461626C6503063Q00756E7061636B000D4Q00DB5Q00024Q00015Q00104Q000100014Q00015Q00104Q000200014Q000100013Q00202Q00010001000300122Q000300043Q00202Q0003000300054Q00048Q000300046Q00013Q00016Q00017Q00023Q00030D3Q0067657453652Q6C52656D6F746503053Q007063612Q6C010D3Q00124A2Q0100014Q00B500010001000200064900010006000100010004603Q000600012Q006B01026Q005C010200023Q00124A010200023Q00068800033Q000100022Q00F08Q00F03Q00014Q00790102000200022Q005C010200024Q000C012Q00013Q00013Q00073Q00026Q00F03F03083Q004974656D4E616D6503063Q00416D6F756E74030F3Q0053652Q6C4261746368416D6F756E74030A3Q004669726553657276657203053Q007461626C6503063Q00756E7061636B000F4Q00F95Q00014Q00013Q00024Q00025Q00102Q00010002000200122Q000200043Q00102Q00010003000200104Q000100014Q000100013Q00202Q00010001000500122Q000300063Q0020480103000300072Q00F000046Q00FA000300044Q006F00013Q00012Q000C012Q00017Q002C3Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003053Q00666F726365030F3Q004175746F53652Q6C456E61626C6564030D3Q006E2Q6564734175746F53652Q6C03093Q006661726D506861736503043Q0073652Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03103Q00636C6561724661726D5761726E696E6703093Q0073652Q6C5F6661696C030D3Q007361766553652Q6C537461746503063Q006D616E75616C2Q01030A3Q00726573756D654661726D031B3Q00D0A2D09F20D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D1833Q2E030D3Q00776F726C6454656C65706F7274030D3Q0053452Q4C5F574F524C445F4944030E3Q00636C65617253652Q6C5374617465030F3Q00707573684661726D5761726E696E6703383Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D182D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18303043Q0069646C6503363Q00D0A2D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18320D0BDD0B520D183D0B4D0B0D0BBD181D18F03253Q00D096D0B4D191D0BC20D0B7D0B0D0B3D180D183D0B7D0BAD18320D0BCD0B8D180D0B03Q2E03133Q0077616974466F72436861726163746572487270026Q00284003123Q0053452Q4C5F574149545F41465445525F5450031F3Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0B5D180D0B2D0B0D0BDD0B0030D3Q006C6F616453652Q6C537461746503053Q00706861736503493Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0BED0B4D0BED0BBD0B6D0B8D182D181D18F20D0BFD0BED181D0BBD0B520D0BFD0B5D180D0B5D0B7D0B0D0B3D180D183D0B7D0BAD0B803203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D7303233Q0053652Q6C4974656D52656D6F746520D0BDD0B5D0B4D0BED181D182D183D0BFD0B5D0BD026Q00F03F03063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q004641524D5F574F524C445F494403343Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0B2D0B5D180D0BDD183D182D18CD181D18F20D0BDD0B020D184D0B0D180D0BC027Q004003123Q0066696E616C697A6553652Q6C526573756D6503323Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD180D0BED0B4D0B0D182D18C2028D0BDD0B5D1822072656D6F74652903213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B002CC3Q00064900010004000100010004603Q000400012Q007001026Q00F0000100023Q00124A010200013Q00061E0102000A00013Q0004603Q000A00012Q006B01025Q00127C010300024Q001D000200033Q00204801020001000300064900020018000100010004603Q0018000100124A010200043Q00064900020012000100010004603Q001200012Q006B01026Q005C010200023Q00124A010200054Q00B500020001000200064900020018000100010004603Q001800012Q006B01026Q005C010200023Q00068800023Q000100012Q00F03Q00013Q00068800030001000100022Q00F03Q00014Q00F07Q00068800040002000100022Q00F03Q00014Q00F08Q000F010500013Q00122Q000500013Q00122Q000500073Q00122Q000500063Q00122Q000500086Q00050001000100122Q000500096Q00050001000100122Q0005000A6Q00050001000100124A0105000B3Q0012110106000C6Q00050002000100122Q0005000D3Q00122Q000600076Q00073Q000200202Q00080001000300262Q000800340001000F0004603Q003400012Q007100086Q006B010800013Q0010320107000E00080020480108000100100026CD0008003A0001000F0004603Q003A00012Q007100086Q006B010800013Q0010D60007001000084Q0005000700014Q000500023Q00122Q000600116Q00050002000100122Q000500123Q00122Q000600136Q00050002000200062Q00050052000100010004603Q0052000100124A010500144Q002801050001000100124A010500153Q00127C0106000C3Q00127C010700164Q00680105000700012Q006B01055Q001297000500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q000600186Q000500034Q00F0000500023Q00123B000600196Q00050002000100122Q0005001A3Q00122Q0006001B6Q0005000200014Q000500033Q00122Q0006001C6Q00050002000200062Q00050066000100010004603Q0066000100124A010500144Q00160105000100014Q00055Q00122Q000500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q0006001D6Q000500033Q00124A0105001E4Q00B500050001000200061E0105006D00013Q0004603Q006D000100204801060005001F0026CD00060074000100070004603Q007400012Q006B01065Q001297000600013Q00122Q000600173Q00122Q000600066Q000600013Q00122Q000700206Q000600034Q00F0000600023Q00128C000700216Q00060002000100122Q000600226Q000700036Q000800046Q00060008000200062Q00060081000100010004603Q0081000100124A010700153Q00127C0108000C3Q00127C010900234Q00680107000900012Q00F0000700033Q00127C010800244Q00790107000200020006490007008F000100010004603Q008F000100124A010700144Q00160107000100014Q00075Q00122Q000700013Q00122Q000700173Q00122Q000700066Q00075Q00122Q0008001D6Q000700033Q00124A0107000D3Q00127C010800254Q007001093Q0002002048010A000100030026CD000A00960001000F0004603Q009600012Q0071000A6Q006B010A00013Q0010320109000E000A002048010A000100100026CD000A009C0001000F0004603Q009C00012Q0071000A6Q006B010A00013Q0010D600090010000A4Q0007000900014Q000700023Q00122Q000800266Q00070002000100122Q000700123Q00122Q000800276Q00070002000200062Q000700AB000100010004603Q00AB000100124A010700153Q00127C0108000C3Q00127C010900284Q006801070009000100124A0107001A3Q0012A80008001B6Q0007000200014Q000700033Q00122Q000800296Q00070002000100122Q0007001E6Q00070001000200062Q000700BC00013Q0004603Q00BC000100204801080007001F0026A0000800BC000100250004603Q00BC000100124A0108002A4Q00F0000900014Q00F0000A00064Q00680108000A00012Q006B01085Q00122C010800013Q00122Q000800173Q00122Q000800063Q00122Q0008000B3Q00122Q0009000C6Q00080002000100062Q000600C8000100010004603Q00C800012Q006B01085Q00127C0109002B4Q001D000800034Q006B010800013Q00127C0109002C4Q001D000800034Q000C012Q00013Q00033Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q00962Q015Q0020482Q010001000100061E2Q01000900013Q0004603Q0009000100124A2Q0100024Q009601025Q0020480102000200012Q00F000036Q00682Q01000300012Q000C012Q00017Q00033Q0003083Q0073652Q6C5761697403053Q00666F72636503053Q0072756E4964010B3Q001213000100016Q00028Q00033Q00024Q00045Q00202Q00040004000200102Q0003000200044Q000400013Q00102Q0003000300044Q000100036Q00019Q0000017Q00033Q0003053Q00666F726365030E3Q0073652Q6C496E50726F6772652Q7303123Q0073686F756C644661726D436F6E74696E7565000B4Q0096016Q002048014Q000100061E012Q000600013Q0004603Q0006000100124A012Q00024Q005C012Q00023Q00124A012Q00034Q00962Q0100014Q0051012Q00014Q00C78Q000C012Q00017Q00053Q00030C3Q0072756E53652Q6C4379636C6503053Q00666F7263650100030A3Q00726573756D654661726D3Q01073Q001279000100016Q00028Q00033Q000200302Q00030002000300302Q0003000400054Q0001000300016Q00017Q00043Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003043Q007461736B03053Q00737061776E01103Q00124A2Q0100013Q00061E2Q01000A00013Q0004603Q000A000100061E012Q000900013Q0004603Q000900012Q00F000016Q006B01025Q00127C010300024Q00682Q01000300012Q000C012Q00013Q00124A2Q0100033Q0020482Q010001000400068800023Q000100012Q00F08Q00E30001000200012Q000C012Q00013Q00013Q000F3Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964026Q00F03F030E3Q006661726D436865636B506175736503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030C3Q0072756E53652Q6C4379636C6503053Q00666F7263652Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303133Q0068617350656E64696E6753652Q6C537461746503093Q0073746172744661726D002E3Q00124A012Q00013Q00061E012Q000600013Q0004603Q0006000100124A2Q0100023Q00206500010001000300128F000100024Q006B2Q0100013Q0012812Q0100043Q00122Q000100053Q00122Q000200066Q00010002000100122Q000100053Q00122Q000200076Q00010002000100122Q000100053Q00122Q000200086Q00010002000100122Q000100096Q000200026Q00033Q000300302Q0003000A000B00102Q0003000C3Q00023501045Q0010320103000D00042Q00A52Q01000300022Q006B01035Q00128F000300043Q00061E012Q002600013Q0004603Q0026000100124A010300013Q00061E0103002600013Q0004603Q0026000100124A0103000E4Q00B500030001000200064900030026000100010004603Q0026000100124A0103000F4Q00280103000100012Q009601035Q00061E0103002D00013Q0004603Q002D00012Q009601036Q00F0000400014Q00F0000500024Q00680103000500012Q000C012Q00013Q00013Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q00124A2Q0100013Q00061E2Q01000900013Q0004603Q0009000100124A2Q0100013Q0020482Q010001000200061E2Q01000900013Q0004603Q0009000100124A2Q0100013Q0010322Q0100034Q000C012Q00017Q00073Q00030F3Q004175746F53652Q6C456E61626C6564030E3Q0073652Q6C496E50726F6772652Q7303043Q007469636B030F3Q006C61737453652Q6C436865636B417403113Q0053652Q6C436865636B496E74657276616C030D3Q006E2Q6564734175746F53652Q6C030B3Q0072756E4175746F53652Q6C01183Q00124A2Q0100013Q00061E2Q01000600013Q0004603Q0006000100124A2Q0100023Q00061E2Q01000700013Q0004603Q000700012Q000C012Q00013Q00124A2Q0100034Q005E2Q010001000200122Q000200046Q00020001000200122Q000300053Q00062Q0002000F000100030004603Q000F00012Q000C012Q00013Q00128F000100043Q00124A010200064Q00B500020001000200061E0102001700013Q0004603Q0017000100124A010200074Q00F000036Q00E30002000200012Q000C012Q00017Q00073Q00030B3Q004661726D456E61626C656403043Q007469636B03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006C6F674661726D53652Q73696F6E446973636F726403153Q00D09ED182D187D191D18220D184D0B0D180D0BCD0B0023Q00806D4C4A4100123Q00124A012Q00013Q0006493Q0004000100010004603Q000400012Q000C012Q00013Q00124A012Q00024Q005E012Q0001000200122Q000100036Q00013Q000100122Q000200043Q00062Q0001000C000100020004603Q000C00012Q000C012Q00013Q00128F3Q00033Q0012CC000100053Q00122Q000200063Q00122Q000300076Q0001000300016Q00017Q000E3Q0003093Q006661726D506861736503063Q0073656172636803103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403123Q0073686F756C644661726D436F6E74696E756503133Q0072656672657368546172676574436F756E7473030F3Q0067657456616C696454617267657473028Q0003043Q0069646C65030E3Q0048756257616974456E61626C6564030B3Q00687562526573745761697403043Q007461736B03043Q0077616974026Q33D33F01313Q001244000100023Q00122Q000100013Q00122Q000100036Q0001000100014Q000100013Q00122Q000100046Q00015Q00124A010200054Q00F000036Q007901020002000200061E0102002C00013Q0004603Q002C000100124A010200064Q00E000020001000100122Q000200076Q0002000100024Q000300023Q000E2Q00080016000100030004603Q0016000100127C010300093Q00128F000300014Q005C010200023Q00124A010300054Q00F000046Q00790103000200020006490003001C000100010004603Q001C00010004603Q002C000100124A0103000A3Q00061E0103002700013Q0004603Q0027000100124A0103000B4Q00F000046Q00C4000500014Q00DD00030005000200064900030026000100010004603Q002600010004603Q002C00012Q006B2Q0100013Q00124A0103000C3Q00204801030003000D00127C0104000E4Q00E30003000200010004603Q0007000100127C010200093Q00128F000200014Q007001026Q005C010200024Q000C012Q00017Q001A3Q00030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q00030D3Q006661726D54696D65546F74616C03043Q007469636B03093Q006661726D506861736503043Q0069646C6503093Q006661726D52756E4964026Q00F03F03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030A3Q0072657365744175746F46030C3Q0069676E6F72656444726F707303123Q0074656C65706F7274436F2Q6E656374696F6E030F3Q006D616E75616C53652Q6C546F6B656E030E3Q0073652Q6C496E50726F6772652Q73030A3Q006661726D546872656164030C3Q006B2Q657052656E646572336403123Q006F6E4661726D52656E646572336453746F70030C3Q0073746F70536166654D6F646501473Q0006493Q0004000100010004603Q000400012Q00702Q016Q00F03Q00013Q00124A2Q0100013Q00061E2Q01001300013Q0004603Q0013000100124A2Q0100023Q000EA701030013000100010004603Q0013000100124A2Q0100043Q00124A010200054Q00B500020001000200124A010300024Q00480002000200032Q004E2Q010001000200128F000100043Q00127C2Q0100033Q00128F000100024Q006B2Q015Q001258000100013Q00122Q000100073Q00122Q000100063Q00122Q000100083Q00202Q00010001000900122Q000100086Q000100013Q00122Q0001000A6Q000100013Q00122Q0001000B3Q00127C2Q01000D3Q00128F0001000C3Q00124A2Q01000E3Q00124A0102000F4Q00E300010002000100124A2Q01000E3Q00124A010200104Q00E300010002000100124A2Q01000E3Q00124A010200114Q00E300010002000100124A2Q01000E3Q00124A010200124Q00E30001000200012Q00702Q015Q00128F000100133Q00124A2Q0100143Q00061E2Q01003600013Q0004603Q0036000100124A2Q01000E3Q00023501026Q00E30001000200012Q0091000100013Q00128F000100143Q00124A2Q0100153Q0020C100010001000900122Q000100156Q00015Q00122Q000100166Q000100013Q00122Q000100173Q00202Q00013Q001800062Q00010043000100010004603Q0043000100124A2Q01000E3Q00124A010200194Q00E300010002000100124A2Q01000E3Q00124A0102001A4Q00E30001000200012Q000C012Q00013Q00013Q00023Q0003123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400043Q00124A012Q00013Q002024014Q00022Q00E33Q000200012Q000C012Q00017Q00013Q00030D3Q006B692Q6C4661726D4C2Q6F707300033Q00124A012Q00014Q0028012Q000100012Q000C012Q00017Q000A3Q00030F3Q00666C75736853617665436F6E66696703083Q0073746F704661726D030C3Q0073746F70536166654D6F6465030E3Q0073746F7043616D6572614C2Q6F7003183Q0064657374726F79426C6F636B65645A6F6E6556697375616C030F3Q00636C65616E757052656E6465723364030C3Q007363722Q656E47756952656603063Q00506172656E7403053Q007063612Q6C03093Q007363722Q656E47756900223Q0012F63Q00018Q0001000100124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00058Q0001000100124A012Q00064Q0028012Q0001000100124A012Q00073Q00061E012Q001700013Q0004603Q0017000100124A012Q00073Q002048014Q000800061E012Q001700013Q0004603Q0017000100124A012Q00093Q0002352Q016Q00E33Q000200010004603Q0021000100124A012Q000A3Q00061E012Q002100013Q0004603Q0021000100124A012Q000A3Q002048014Q000800061E012Q002100013Q0004603Q0021000100124A012Q00093Q0002352Q0100014Q00E33Q000200012Q000C012Q00013Q00023Q00023Q00030C3Q007363722Q656E47756952656603073Q0044657374726F7900043Q00124A012Q00013Q002024014Q00022Q00E33Q000200012Q000C012Q00017Q00023Q0003093Q007363722Q656E47756903073Q0044657374726F7900043Q00124A012Q00013Q002024014Q00022Q00E33Q000200012Q000C012Q00017Q00023Q00030B3Q00736F6674436C65616E7570030D3Q00726573746F726543616D65726100053Q00123C3Q00018Q0001000100124Q00028Q000100016Q00017Q00123Q00030D3Q006B692Q6C4661726D4C2Q6F7073030C3Q006B2Q657052656E64657233642Q01030B3Q004661726D456E61626C6564030F3Q006661726D54696D655374617274656403043Q007469636B03103Q006C6173744661726D5265706F7274417403093Q006661726D52756E496403133Q006F6E4661726D52656E6465723364537461727403043Q007461736B03053Q006465666572030D3Q007374617274536166654D6F646503123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374030A3Q006661726D54687265616403053Q00737061776E00213Q00125D3Q00016Q00013Q000100302Q0001000200036Q000200016Q00013Q00124Q00043Q00124Q00068Q0001000200124Q00053Q00124Q00064Q00B53Q000100020012C03Q00073Q00124Q00083Q00122Q000100096Q00010001000100122Q0001000A3Q00202Q00010001000B00122Q0002000C6Q00010002000100122Q0001000E3Q00202Q00010001000F0020242Q010001001000068800033Q000100012Q00F08Q00DD00010003000200128F0001000D3Q00124A2Q01000A3Q0020482Q010001001200068800020001000100012Q00F08Q00792Q010002000200128F000100114Q000C012Q00013Q00023Q000C3Q0003123Q0073686F756C644661726D436F6E74696E756503093Q006661726D506861736503073Q00636F2Q6C65637403043Q007761697403043Q0073652Q6C2Q033Q0068756203063Q0073656172636803063Q0074726176656C03043Q006D696E6503113Q0063752Q72656E745461726765745061727403053Q007063612Q6C03103Q0074656C65706F7274546F54617267657400233Q00124A012Q00014Q00962Q016Q0079012Q000200020006493Q0006000100010004603Q000600012Q000C012Q00013Q00124A012Q00023Q0026CD3Q0018000100030004603Q0018000100124A012Q00023Q0026CD3Q0018000100040004603Q0018000100124A012Q00023Q0026CD3Q0018000100050004603Q0018000100124A012Q00023Q0026CD3Q0018000100060004603Q0018000100124A012Q00023Q0026CD3Q0018000100070004603Q0018000100124A012Q00023Q0026A03Q0019000100080004603Q001900012Q000C012Q00013Q00124A012Q00023Q0026A03Q0022000100090004603Q0022000100124A012Q000A3Q00061E012Q002200013Q0004603Q0022000100124A012Q000B3Q00124A2Q01000C4Q00E33Q000200012Q000C012Q00017Q000D3Q0003123Q0073686F756C644661726D436F6E74696E756503053Q007063612Q6C030D3Q00697343616E63656C452Q726F7203043Q007761726E03103Q005B4D415849204855425D206661726D3A03043Q007461736B03043Q0077616974026Q00E03F03093Q006661726D52756E496403113Q0063752Q72656E7454617267657450617274030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0069646C65002E4Q006B016Q00124A2Q0100014Q009601026Q00792Q010002000200061E2Q01002200013Q0004603Q0022000100124A2Q0100023Q00068800023Q000100022Q0096017Q00F08Q00B300010002000200064900010001000100010004603Q0001000100124A010300034Q00F0000400024Q007901030002000200061E0103001300013Q0004603Q001300010004603Q0022000100124A010300043Q00127C010400054Q00F0000500024Q006801030005000100124A010300014Q009601046Q00790103000200020006490003001D000100010004603Q001D00010004603Q0022000100124A010300063Q00204801030003000700127C010400084Q00E30003000200010004603Q000100012Q00962Q015Q00124A010200093Q00069C0001002D000100020004603Q002D00012Q0091000100013Q00128F0001000A3Q00124A2Q01000B3Q0006490001002D000100010004603Q002D000100127C2Q01000D3Q00128F0001000C4Q000C012Q00013Q00013Q003D3Q0003103Q006D6179626552756E4175746F53652Q6C03123Q0073686F756C644661726D436F6E74696E756503123Q006D6179626552756E4661726D5265706F727403123Q0063617074757265487562506F736974696F6E030E3Q0048756257616974456E61626C6564030B3Q006875625265737457616974030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473028Q00030E3Q0072756E536561726368506861736503043Q007461736B03043Q0077616974029A5Q99C93F030E3Q007069636B42657374546172676574030A3Q006163746976654E6F646503043Q006E6F646503103Q006163746976655461726765744B696E6403043Q006B696E64030A3Q006F72626974416E676C65030A3Q0072657365744175746F4603113Q00676574546172676574486974626F786573030F3Q00707573684661726D5761726E696E6703093Q006E6F5F686974626F7803193Q00D0A320D186D0B5D0BBD0B820D0BDD0B5D18220486974626F78026Q00E03F03103Q00636C6561724661726D5761726E696E6703113Q0063752Q72656E7454617267657450617274026Q00F03F030F3Q0067657450617274506F736974696F6E03103Q006765744D696E65416E63686F72506F7303183Q0067657454656C65706F7274486569676874466F724B696E6403073Q00566563746F72332Q033Q006E657703013Q005803013Q005903013Q005A03093Q006661726D506861736503063Q0074726176656C030C3Q0054656C65706F72744D6F646503063Q00736D2Q6F7468030D3Q0074656C65706F7274487270546F03053Q0072756E496403043Q006D696E6503043Q007469636B026Q004E40030D3Q006973546172676574416C697665030B3Q007570646174654175746F46030B3Q006175746F46416374697665030C3Q00737475636B5F6D696E696E67032D3Q00D094D0BED0BBD0B3D0BE20D0BDD0B520D0BBD0BED0BCD0B0D0B5D182D181D18F20E2809420D0B6D0BCD1832046030A3Q00612Q7461636B50617274030B3Q00412Q7461636B44656C617903103Q0072656C656173654D6F757365486F6C6403053Q0073746F6E6503123Q0073652Q73696F6E53746F6E65734D696E656403113Q0073652Q73696F6E54722Q65734D696E656403103Q0077616974416E645363616E44726F7073030F3Q00636F2Q6C656374412Q6C44726F707303043Q0074722Q6503133Q0073746F704368617261637465724D6F74696F6E03143Q0072657475726E546F48756241667465724E6F646500E83Q00124A012Q00014Q00962Q016Q00E33Q0002000100124A012Q00024Q00962Q016Q0079012Q000200020006493Q0009000100010004603Q000900012Q000C012Q00013Q00124A012Q00034Q00B03Q0001000100124Q00026Q00019Q000002000200064Q0011000100010004603Q001100012Q000C012Q00014Q0096012Q00013Q0006493Q0021000100010004603Q002100012Q006B012Q00014Q00EA3Q00013Q00124Q00048Q0001000100124Q00053Q00064Q002100013Q0004603Q0021000100124A012Q00064Q00962Q016Q0079012Q000200020006493Q0021000100010004603Q002100012Q000C012Q00013Q00124A012Q00074Q00B53Q0001000200124A2Q0100084Q00282Q01000100012Q001900015Q0026A00001003B000100090004603Q003B000100124A2Q01000A4Q002601028Q0001000200026Q00013Q00122Q000100026Q00028Q00010002000200062Q0001003400013Q0004603Q003400012Q001900015Q0026A000010039000100090004603Q0039000100124A2Q01000B3Q0020482Q010001000C00127C0102000D4Q00E30001000200012Q000C012Q00013Q00124A2Q0100084Q00282Q010001000100124A2Q01000E4Q00F000026Q00792Q010002000200064900010045000100010004603Q0045000100124A0102000B3Q00204801020002000C00127C0103000D4Q00E30002000200012Q000C012Q00013Q0020480102000100100012100102000F3Q00202Q00020001001200122Q000200113Q00122Q000200093Q00122Q000200133Q00122Q000200146Q00020001000100122Q000200153Q00122Q0003000F3Q00122Q000400116Q0002000400024Q000300023Q00262Q0003005D000100090004603Q005D000100124A010300163Q001252000400173Q00122Q000500186Q00030005000100122Q0003000B3Q00202Q00030003000C00122Q000400196Q0003000200016Q00013Q00124A0103001A3Q001234010400176Q00030002000100202Q00030002001C00122Q0003001B3Q00122Q0003001D3Q00122Q0004001B6Q00030002000200062Q0003008700013Q0004603Q0087000100124A0104001E3Q00126A0005000F3Q00122Q000600116Q000700036Q00040007000200122Q0005001F3Q00122Q000600116Q00050002000200122Q000600203Q00202Q00060006002100202Q00070004002200202Q0008000400234Q00080008000500202Q0009000400244Q00060009000200122Q000700263Q00122Q000700253Q00122Q000700273Q00262Q0007007C000100280004603Q007C00012Q007100076Q006B010700013Q00124A010800294Q00F0000900064Q0070010A3Q0002001032010A002800072Q0096010B5Q001032010A002A000B2Q00DD0008000A000200064900080087000100010004603Q008700012Q000C012Q00013Q00127C0104002B3Q00128F000400253Q00124A0104002C4Q00B500040001000200206500040004002D00124A010500024Q009601066Q007901050002000200061E010500B500013Q0004603Q00B5000100124A0105002C4Q00B5000500010002000617010500B5000100040004603Q00B5000100124A0105002E3Q00124A0106000F3Q00124A010700114Q00DD00050007000200061E010500B500013Q0004603Q00B5000100124A0105002F3Q00123D0106000F3Q00122Q000700116Q00050007000100122Q000500303Q00062Q000500A700013Q0004603Q00A7000100124A010500163Q00127C010600313Q00127C010700324Q00680105000700010004603Q00AA000100124A0105001A3Q00127C010600314Q00E300050002000100124A010500333Q00124A0106001B4Q00E300050002000100124A010500343Q000EA70109008C000100050004603Q008C000100124A0105000B3Q00204801050005000C00124A010600344Q00E30005000200010004603Q008C000100124A010500024Q009601066Q0079010500020002000649000500BB000100010004603Q00BB00012Q000C012Q00013Q00127C010500093Q00128F010500133Q00122Q000500356Q0005000100014Q000500053Q00122Q0005001B3Q00122Q000500113Q00262Q000500C8000100360004603Q00C8000100124A010500373Q00206500050005001C00128F000500373Q0004603Q00CB000100124A010500383Q00206500050005001C00128F000500383Q00124A010500393Q00129A0006000F6Q00078Q00050007000100122Q000500026Q00068Q00050002000200062Q000500D5000100010004603Q00D500012Q000C012Q00013Q00124A0105003A3Q00124A0106000F4Q009601076Q00680105000700012Q0091000500053Q00128F0005000F3Q00127C0105003B3Q00128F000500114Q0091000500053Q00128F0005001B3Q00124A0105003C4Q00B000050001000100122Q0005003D6Q00068Q00050002000200062Q000500E7000100010004603Q00E700012Q000C012Q00014Q000C012Q00017Q00143Q0003073Q00656E61626C6564030B3Q004661726D456E61626C6564030B3Q006661726D5365636F6E6473030E3Q006765744661726D5365636F6E647303053Q00706861736503093Q006661726D506861736503053Q0074722Q6573030F3Q0063616368656454722Q65436F756E7403063Q0073746F6E657303103Q0063616368656453746F6E65436F756E7403053Q0064726F7073030F3Q0063616368656444726F70436F756E7403093Q0074722Q6544726F707303103Q0073652Q73696F6E54722Q6544726F7073030A3Q0073746F6E6544726F707303113Q0073652Q73696F6E53746F6E6544726F7073030A3Q0074722Q65734D696E656403113Q0073652Q73696F6E54722Q65734D696E6564030B3Q0073746F6E65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E656400184Q007F014Q000A00122Q000100023Q00104Q0001000100122Q000100046Q00010001000200104Q0003000100122Q000100063Q00104Q0005000100122Q000100083Q00104Q0007000100122Q0001000A3Q00104Q0009000100122Q0001000C3Q00104Q000B000100122Q0001000E3Q00104Q000D000100122Q000100103Q00104Q000F000100122Q000100123Q00104Q0011000100122Q000100143Q00104Q001300016Q00028Q00017Q000A3Q00030E3Q006661726D436865636B506175736503103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q00426C6F636B5569447572696E674661726D030B3Q004661726D456E61626C656403043Q0067656E7603153Q004D617869487562496E76556E626C6F636B656455692Q01030C3Q0073746F70536166654D6F646500134Q00B43Q00013Q00124Q00013Q00124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00053Q00064Q001200013Q0004603Q0012000100124A012Q00063Q00061E012Q001200013Q0004603Q0012000100124A012Q00073Q00309F012Q0008000900124A012Q000A4Q0028012Q000100012Q000C012Q00017Q00073Q00030E3Q006661726D436865636B506175736503043Q0067656E7603153Q004D617869487562496E76556E626C6F636B65645569030B3Q004661726D456E61626C656403113Q00426C6F636B5569447572696E674661726D00030D3Q007374617274536166654D6F646500114Q0015016Q00124Q00013Q00124Q00023Q00206Q000300064Q001000013Q0004603Q0010000100124A012Q00043Q00061E012Q001000013Q0004603Q0010000100124A012Q00053Q00061E012Q001000013Q0004603Q0010000100124A012Q00023Q00309F012Q0003000600124A012Q00074Q0028012Q000100012Q000C012Q00017Q000C3Q0003043Q007479706503063Q00737472696E67034Q002Q033Q00737562026Q00F03F03013Q003C026Q00794003053Q006C6F77657203043Q0066696E6403093Q003C21646F63747970650003053Q003C68746D6C01273Q00124A2Q0100014Q00F000026Q00792Q01000200020026A00001000D000100020004603Q000D00010026CD3Q000D000100030004603Q000D00010020242Q013Q000400127C010300053Q00127C010400054Q00DD0001000400020026CD0001000F000100060004603Q000F00012Q006B2Q016Q005C2Q0100023Q0020242Q013Q000400127C010300053Q00127C010400074Q00DD0001000400020020242Q01000100082Q00792Q010002000200202401020001000900127C0104000A3Q00127C010500054Q006B010600014Q00DD0002000600020026A0000200240001000B0004603Q0024000100202401020001000900127C0104000C3Q00127C010500054Q006B010600014Q00DD0002000600020026A0000200240001000B0004603Q002400012Q007100026Q006B010200014Q005C010200024Q000C012Q00017Q00063Q0003043Q0067616D6503073Q00482Q747047657403123Q006D6178692D6875622D75692E6C75613F763D03083Q00746F737472696E6703023Q006F7303043Q0074696D65000E3Q0012383Q00013Q00206Q00024Q00025Q00122Q000300033Q00122Q000400043Q00122Q000500053Q00202Q0005000500064Q000500016Q00043Q00024Q0002000200044Q000300018Q00039Q008Q00017Q004C3Q0003103Q006C6F61644368616E67656C6F674C6962030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C6973745772617003043Q0067656E76030E3Q004D61786948756256657273696F6E03083Q00746F737472696E67030E3Q005343524950545F56455253494F4E03073Q0063752Q72656E742Q033Q00E2809403083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D32026Q00F03F028Q00026Q00424003103Q004261636B67726F756E64436F6C6F723303063Q00434F4C4F525303053Q0070616E656C030F3Q00426F7264657253697A65506978656C03043Q00466F6E7403043Q00456E756D030A3Q00476F7468616D426F6C6403083Q005465787453697A65026Q002840030A3Q0054657874436F6C6F723303063Q00612Q63656E7403043Q005465787403013Q004C03113Q006368616E67656C6F675F63752Q72656E7403023Q003A20030B3Q004C61796F75744F7264657203063Q00506172656E7403093Q00612Q64436F726E6572026Q00204003093Q00554950612Q64696E67030B3Q0050612Q64696E674C65667403043Q005544696D030C3Q0050612Q64696E675269676874027Q004003073Q00656E747269657303043Q007479706503053Q007461626C6503063Q0069706169727303073Q006368616E67657303053Q004672616D65030D3Q004175746F6D6174696353697A6503013Q0059030A3Q0050612Q64696E67546F70026Q002440030D3Q0050612Q64696E67426F2Q746F6D030C3Q0055494C6973744C61796F757403093Q00536F72744F7264657203073Q0050612Q64696E67026Q00184003073Q0076657273696F6E03063Q00737472696E6703043Q0064617465034Q00026Q00324003163Q004261636B67726F756E645472616E73706172656E637903043Q0074657874030E3Q005465787458416C69676E6D656E7403043Q004C65667403043Q0020C2B72003063Q00476F7468616D026Q00264003053Q006D75746564030B3Q00546578745772612Q7065642Q0103043Q00E280A220026Q004840026Q002A40030D3Q006368616E67656C6F675F776970030E3Q0072656769737465724C6F63616C65024A012Q0012A5000200016Q00020001000200202Q0003000100024Q00048Q00030002000200202Q0004000100034Q000500036Q00040002000200122Q000500043Q00202Q00050005000500062Q0005001200013Q0004603Q0012000100124A010500063Q00124A010600043Q0020480106000600052Q00790105000200020006490005001B000100010004603Q001B000100124A010500073Q0006490005001B000100010004603Q001B000100061E0102001A00013Q0004603Q001A00010020480105000200080006490005001B000100010004603Q001B000100127C010500093Q00124A0106000A3Q00204001060006000B00122Q0007000C6Q00060002000200122Q0007000E3Q00202Q00070007000B00122Q0008000F3Q00122Q000900103Q00122Q000A00103Q00122Q000B00116Q0007000B000200102Q0006000D000700202Q00070001001300202Q00070007001400102Q00060012000700302Q00060015001000122Q000700173Q00202Q00070007001600202Q00070007001800102Q00060016000700302Q00060019001A00202Q00070001001300202Q00070007001C00102Q0006001B000700122Q0007001E3Q00122Q0008001F6Q00070002000200122Q000800206Q000900056Q00070007000900102Q0006001D000700302Q00060021000F00102Q00060022000400202Q0007000100234Q000800063Q00122Q000900246Q00070009000100122Q0007000A3Q00202Q00070007000B00122Q000800256Q00070002000200122Q000800273Q00202Q00080008000B00122Q000900103Q00122Q000A001A6Q0008000A000200102Q00070026000800122Q000800273Q00202Q00080008000B00122Q000900103Q00122Q000A001A6Q0008000A000200102Q00070028000800102Q00070022000600122Q000800293Q00062Q00090055000100020004603Q0055000100204801090002002A00124A010A002B4Q00F0000B00094Q0079010A000200020026A0000A00232Q01002C0004603Q00232Q012Q0019000A00093Q000EA7011000232Q01000A0004603Q00232Q0100124A010A002D4Q00F0000B00094Q00B3000A0002000C0004603Q00202Q0100124A010F002B4Q00F00010000E4Q0079010F000200020026A0000F00202Q01002C0004603Q00202Q0100124A010F002B3Q0020480110000E002E2Q0079010F000200020026A0000F00202Q01002C0004603Q00202Q01002048010F000E002E2Q0019000F000F3Q000EA7011000202Q01000F0004603Q00202Q0100124A010F000A3Q002048010F000F000B00127C0110002F4Q0079010F0002000200124A0110000E3Q00207301100010000B00122Q0011000F3Q00122Q001200103Q00122Q001300103Q00122Q001400106Q001000140002001032010F000D001000124A011000173Q002048011000100030002048011000100031001032010F00300010002048011000010013002048011000100014001032010F0012001000309F010F00150010001032010F0021000800206500080008000F00105B010F0022000400202Q0010000100234Q0011000F3Q00122Q001200246Q00100012000100122Q0010000A3Q00202Q00100010000B00122Q001100256Q00100002000200122Q001100273Q00204801110011000B001254001200103Q00122Q001300336Q00110013000200102Q00100032001100122Q001100273Q00202Q00110011000B00122Q001200103Q00122Q001300336Q00110013000200102Q00100034001100124A011100273Q00204801110011000B001254001200103Q00122Q0013001A6Q00110013000200102Q00100026001100122Q001100273Q00202Q00110011000B00122Q001200103Q00122Q0013001A6Q00110013000200102Q00100028001100105A01100022000F00122Q0011000A3Q00202Q00110011000B00122Q001200356Q00110002000200122Q001200173Q00202Q00120012003600202Q00120012002100102Q00110036001200122Q001200273Q00204801120012000B0012AB011300103Q00122Q001400386Q00120014000200102Q00110037001200102Q00110022000F00122Q0012002B3Q00202Q0013000E00394Q00120002000200262Q001200BE0001003A0004603Q00BE00010020480112000E0039000649001200BF000100010004603Q00BF000100127C011200093Q00124A0113002B3Q0020480114000E003B2Q00790113000200020026A0001300C70001003A0004603Q00C700010020480113000E003B000649001300C8000100010004603Q00C8000100127C0113003C3Q00124A0114000A3Q00203A01140014000B00122Q0015000C6Q00140002000200122Q0015000E3Q00202Q00150015000B00122Q0016000F3Q00122Q001700103Q00122Q001800103Q00122Q0019003D6Q00150019000200102Q0014000D001500302Q0014003E000F00122Q001500173Q00202Q00150015001600202Q00150015001800102Q00140016001500302Q00140019001A00202Q00150001001300202Q00150015003F00102Q0014001B001500122Q001500173Q00202Q00150015004000202Q00150015004100102Q0014004000154Q001500123Q00262Q001300E90001003C0004603Q00E9000100127C011600424Q00F0001700134Q000B011600160017000649001600EA000100010004603Q00EA000100127C0116003C4Q000B0115001500160010930114001D001500302Q00140021000F00102Q00140022000F00122Q0015002D3Q00202Q0016000E002E4Q00150002001700044Q001E2Q0100124A011A002B4Q00F0001B00194Q0079011A000200020026A0001A001E2Q01003A0004603Q001E2Q010026CD0019001E2Q01003C0004603Q001E2Q0100124A011A000A3Q002048011A001A000B00127C011B000C4Q0079011A0002000200124A011B000E3Q002073011B001B000B00122Q001C000F3Q00122Q001D00103Q00122Q001E00103Q00122Q001F00106Q001B001F0002001032011A000D001B00124A011B00173Q002048011B001B0030002048011B001B00310010AA011A0030001B00302Q001A003E000F00122Q001B00173Q00202Q001B001B001600202Q001B001B004300102Q001A0016001B00302Q001A0019004400202Q001B0001001300202Q001B001B004500102Q001A001B001B00309F011A0046004700124A011B00173Q002048011B001B0040002048011B001B0041001032011A0040001B00127C011B00484Q00F0001C00194Q000B011B001B001C001032011A001D001B002065001B0018000F001032011A0021001B001032011A0022000F0006A2001500F2000100020004603Q00F200010006A2000A0061000100020004603Q006100010004603Q00492Q0100124A010A000A3Q002048010A000A000B00127C010B000C4Q0079010A0002000200124A010B000E3Q002073010B000B000B00122Q000C000F3Q00122Q000D00103Q00122Q000E00103Q00122Q000F00496Q000B000F000200108D010A000D000B00202Q000B0001001300202Q000B000B001400102Q000A0012000B00302Q000A0015001000122Q000B00173Q00202Q000B000B001600202Q000B000B004300102Q000A0016000B00302Q000A0019004A002048010B000100130020D3000B000B004500102Q000A001B000B00122Q000B001E3Q00122Q000C004B6Q000B0002000200102Q000A001D000B00302Q000A0021002900102Q000A0022000400202Q000B000100234Q000C000A3Q00127C010D00244Q0068010B000D000100124A010B004C4Q00F0000C000A3Q00127C010D004B4Q0068010B000D00012Q000C012Q00017Q003D3Q0003083Q0074656C656772616D030D3Q0054454C454752414D5F4C494E4B030A3Q007363726970744C696E6503013Q004C030B3Q007363726970745F6C696E65030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C6973745772617003083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D32026Q00F03F028Q00026Q00504003103Q004261636B67726F756E64436F6C6F723303063Q00434F4C4F525303053Q0070616E656C030F3Q00426F7264657253697A65506978656C03043Q00466F6E7403043Q00456E756D03063Q00476F7468616D03083Q005465787453697A65026Q002840030A3Q0054657874436F6C6F723303043Q0074657874030B3Q00546578745772612Q7065642Q0103043Q0054657874030C3Q005343524950545F5449544C4503013Q000A030E3Q00637265646974735F7468616E6B73030B3Q004C61796F75744F7264657203063Q00506172656E7403113Q006372656469747341626F75744C6162656C03093Q00612Q64436F726E6572026Q00204003093Q00554950612Q64696E67030A3Q0050612Q64696E67546F7003043Q005544696D026Q002440030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E675269676874030A3Q005465787442752Q746F6E026Q00444003063Q00612Q63656E74030A3Q00476F7468616D426F6C64026Q002A4003023Q00626703093Q0074675F62752Q746F6E030F3Q004175746F42752Q746F6E436F6C6F720100027Q0040030F3Q0063726564697473546742752Q746F6E030E3Q0072656769737465724C6F63616C65026Q002Q4003163Q004261636B67726F756E645472616E73706172656E637903053Q006D75746564026Q00084003113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E656374039C3Q00064900020004000100010004603Q000400012Q007001036Q00F0000200033Q00204801030002000100064900030008000100010004603Q0008000100124A010300023Q0020480104000200030006490004000E000100010004603Q000E000100124A010400043Q00127C010500054Q00790104000200020020480105000100062Q00FD00068Q00050002000200202Q0006000100074Q000700056Q00060002000200122Q000700083Q00202Q00070007000900122Q0008000A6Q00070002000200122Q0008000C3Q00202Q00080008000900122Q0009000D3Q00122Q000A000E3Q00122Q000B000E3Q00122Q000C000F6Q0008000C000200102Q0007000B000800202Q00080001001100202Q00080008001200102Q00070010000800302Q00070013000E00122Q000800153Q00202Q00080008001400202Q00080008001600102Q00070014000800302Q00070017001800202Q00080001001100202Q00080008001A00102Q00070019000800302Q0007001B001C00122Q0008001E3Q00122Q0009001F6Q000A00043Q00122Q000B001F3Q00122Q000C00043Q00122Q000D00206Q000C000200024Q00080008000C00102Q0007001D000800302Q00070021000D00102Q00070022000600122Q000700233Q00202Q0008000100244Q000900073Q00122Q000A00256Q0008000A000100122Q000800083Q00202Q00080008000900122Q000900266Q00080002000200122Q000900283Q00202Q00090009000900122Q000A000E3Q00122Q000B00296Q0009000B000200102Q00080027000900122Q000900283Q00202Q00090009000900122Q000A000E3Q00122Q000B00186Q0009000B000200102Q0008002A000900122Q000900283Q00202Q00090009000900122Q000A000E3Q00122Q000B00186Q0009000B000200102Q0008002B000900102Q00080022000700122Q000900083Q00202Q00090009000900122Q000A002C6Q00090002000200122Q000A000C3Q00202Q000A000A000900122Q000B000D3Q00122Q000C000E3Q00122Q000D000E3Q00122Q000E002D6Q000A000E000200108D0109000B000A00202Q000A0001001100202Q000A000A002E00102Q00090010000A00302Q00090013000E00122Q000A00153Q00202Q000A000A001400202Q000A000A002F00102Q00090014000A00302Q000900170030002048010A00010011002022010A000A003100102Q00090019000A00122Q000A00043Q00122Q000B00326Q000A0002000200102Q0009001D000A00302Q00090033003400302Q00090021003500102Q00090022000600122Q000900363Q00124A010A00374Q008B010B00093Q00122Q000C00326Q000A000C000100202Q000A000100244Q000B00093Q00122Q000C00256Q000A000C000100122Q000A00083Q00202Q000A000A000900122Q000B000A4Q0079010A0002000200124A010B000C3Q002073010B000B000900122Q000C000D3Q00122Q000D000E3Q00122Q000E000E3Q00122Q000F00386Q000B000F00020010AA010A000B000B00302Q000A0039000D00122Q000B00153Q00202Q000B000B001400202Q000B000B001600102Q000A0014000B00302Q000A0017002900202Q000B0001001100202Q000B000B003A00102Q000A0019000B00309F010A001B001C001072010A001D000300302Q000A0021003B00102Q000A0022000600202Q000B0009003C00202Q000B000B003D000688000D3Q000100022Q00F03Q00034Q00F03Q00094Q0068010B000D00012Q000C012Q00013Q00013Q00073Q0003053Q007063612Q6C03043Q005465787403013Q004C03093Q0074675F636F7069656403043Q007461736B03053Q0064656C6179026Q00F83F00103Q00124A012Q00013Q00068800013Q000100012Q0096017Q0021012Q000200016Q00013Q00122Q000100033Q00122Q000200046Q00010002000200104Q0002000100124Q00053Q00206Q000600122Q000100073Q00068800020001000100012Q0096012Q00014Q0068012Q000200012Q000C012Q00013Q00023Q00013Q00030C3Q00736574636C6970626F61726400043Q00124A012Q00014Q00962Q016Q00E33Q000200012Q000C012Q00017Q00043Q0003063Q00506172656E7403043Q005465787403013Q004C03093Q0074675F62752Q746F6E000A4Q0096016Q002048014Q000100061E012Q000900013Q0004603Q000900012Q0096016Q00124A2Q0100033Q00127C010200044Q00792Q0100020002001032012Q000200012Q000C012Q00017Q0043012Q00030F3Q00687562422Q6F74737472612Q706564030A3Q006C6F6164436F6E66696703043Q0067656E76030E3Q004D61786948756256657273696F6E030E3Q005343524950545F56455253494F4E030D3Q006C6F61644C6F63616C654C6962030A3Q006C6F61644573704C696203103Q007265667265736850686173655465787403073Q0074616244656673030A3Q006765745461624465667303023Q007569030C3Q004D61786948756255494C696203063Q0063726561746503063Q00706C6179657203093Q00706C6179657247756903053Q007469746C65030C3Q005343524950545F5449544C4503073Q0076657273696F6E03083Q00746F737472696E67034Q0003073Q006775694E616D6503083Q004755495F4E414D45030D3Q007361766564506F736974696F6E030A3Q0073617665645569506F73030F3Q0064656661756C74506F736974696F6E030E3Q0044454641554C545F55495F504F53030C3Q00646973706C61794F72646572024Q007E842E4103093Q007469746C6548696E7403013Q004C030A3Q007469746C655F68696E74030C3Q006869646548696E745465787403093Q00686964655F68696E7403083Q006C616E6775616765030A3Q0055694C616E677561676503103Q006F6E4C616E67756167654368616E6765030D3Q0073657455694C616E6775616765030E3Q0072656769737465724C6F63616C65030E3Q006D6F62696C6553746F7054657874030F3Q006D6F62696C655F62746E5F73746F70030E3Q006D6F62696C654D656E7554657874030F3Q006D6F62696C655F62746E5F6D656E7503103Q006F6E4D6F62696C654661726D53746F7003123Q006F6E4D6F62696C654D656E75546F2Q676C6503043Q0074616273030D3Q006B657953746174757354657874030E3Q006F6E53617665506F736974696F6E03123Q007363686564756C6553617665436F6E66696703093Q006F6E44657374726F79030A3Q0066752Q6C556E6C6F6164030D3Q006F6E43616D6572615374617274030F3Q00737461727443616D6572614C2Q6F7003063Q00434F4C4F5253030C3Q00636F6E74656E74506167657303093Q00612Q64436F726E657203093Q0073776974636854616203103Q006D616B6553656374696F6E5469746C65030A3Q006D616B65546F2Q676C65030A3Q006D616B65536C69646572030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C69737457726170030D3Q006D616B65466C6F7750616E656C030B3Q006D616B6553746174526F77030E3Q006D616B65466C6F77546F2Q676C65030E3Q006D616B65466C6F77536C6964657203093Q007363722Q656E47756903063Q007569522Q6F7403063Q007569426F6479030C3Q007363722Q656E477569526566030C3Q006D61696E4672616D6552656603133Q00666F726D617453652Q73696F6E54696D65556903103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503113Q0073652Q73696F6E537461744C6162656C73030C3Q007365744661726D537461746503083Q006D61696E50616765026Q00F03F030D3Q00636F6E74726F6C7350616E656C030E3Q0070616E656C5F636F6E74726F6C7303093Q0055495F4C41594F555403073Q0050414E454C5F57026Q006940028Q0003103Q00746F2Q676C655F6175746F7374617274030D3Q004175746F53746172744661726D02295C8FC2F528CC3F030F3Q00746F2Q676C655F6175746F6661726D027Q0040026Q00E03F030D3Q00746F2Q676C655F72656A6F696E030E3Q0052656A6F696E4175746F4C6F6164026Q00084002F6285C8FC2F5E83F030C3Q0073652Q73696F6E50616E656C030D3Q0070616E656C5F73652Q73696F6E03073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58030E3Q0053452Q53494F4E5F424F44595F5903053Q007068617365030B3Q00737461745F73746174757303053Q0074722Q6573030A3Q00737461745F74722Q657303063Q0073746F6E6573030B3Q00737461745F73746F6E657303043Q006C2Q6F7403093Q00737461745F6C2Q6F74026Q00104003043Q0074696D6503093Q00737461745F74696D65026Q00144003043Q006D6F646503093Q00737461745F6D6F6465026Q001840030C3Q00736C696465727350616E656C030F3Q0070616E656C5F74705F68656967687403063Q0046552Q4C5F57030E3Q00534C494445525F50414E454C5F4803063Q00524F57335F59030D3Q00534C494445525F424F44595F59030C3Q00736C696465725F74722Q6573026Q002840030E3Q0054656C65706F7274486569676874030D3Q00534C494445525F595F53544550030D3Q00736C696465725F73746F6E657303133Q0053746F6E6554656C65706F7274486569676874030B3Q007374617475734C6162656C03083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D3203073Q0056697369626C65010003063Q00506172656E7403093Q007365745363726F2Q6C03073Q0073657457726170030C3Q00536574412Q7472696275746503123Q004D61786948756243617264546F2Q676C6573030B3Q007365635F7461726765747303113Q00746F2Q676C655F6661726D5F74722Q657303103Q004661726D54722Q6573456E61626C656403123Q00746F2Q676C655F6661726D5F73746F6E657303113Q004661726D53746F6E6573456E61626C656403153Q00746F2Q676C655F7461726765745F6E656172657374030E3Q005461726765745069636B4D6F646503073Q006E65617265737403143Q00746F2Q676C655F7461726765745F72616E646F6D03063Q0072616E646F6D030C3Q007365635F74656C65706F727403103Q00746F2Q676C655F74705F736D2Q6F7468030C3Q0054656C65706F72744D6F646503063Q00736D2Q6F746803133Q00736C696465725F74705F737465705F73697A65026Q00444003103Q0054656C65706F72745374657053697A6503143Q00736C696465725F74705F737465705F64656C6179027B14AE47E17A943F026Q33D33F03113Q0054656C65706F72745374657044656C617903133Q00736C696465725F612Q7461636B5F64656C6179026Q00F83F030B3Q00412Q7461636B44656C6179030A3Q007365635F6D696E696E67030C3Q00746F2Q676C655F6F72626974030C3Q004F72626974456E61626C6564030A3Q00746F2Q676C655F61696D030B3Q0041696D4174546172676574030B3Q00746F2Q676C655F666B657903073Q00557365464B6579030C3Q00746F2Q676C655F636C69636B03083Q00557365436C69636B03123Q00746F2Q676C655F6C656769745F6D6F75736503113Q004C656769744D6F7573654361707475726503123Q00736C696465725F6F726269745F73702Q6564030A3Q004F7262697453702Q656403113Q00736C696465725F6F726269745F73697A65026Q003E40030D3Q004F726269744469616D65746572030F3Q007365635F706572666F726D616E636503113Q0073657452656E6465723364546F2Q676C65030F3Q00746F2Q676C655F72656E646572336403103Q0052656E646572336444697361626C656403143Q00746F2Q676C655F72656E64657233645F6661726D03123Q004175746F52656E64657233644F6E4661726D03133Q00746F2Q676C655F626C61636B5F7363722Q656E03123Q00426C61636B5363722Q656E4F7665726C6179030A3Q007365635F736166657479030F3Q00746F2Q676C655F626C6F636B5F756903113Q00426C6F636B5569447572696E674661726D03133Q00746F2Q676C655F626C6F636B5F747261646573030B3Q00426C6F636B547261646573030A3Q007365635F616E74697470030D3Q00746F2Q676C655F616E7469747003133Q00426C6F636B65645A6F6E6573456E61626C6564030A3Q007A6F6E6542746E526F7703053Q004672616D65026Q00424003163Q004261636B67726F756E645472616E73706172656E6379030B3Q004C61796F75744F72646572030C3Q007A6F6E65506C61636542746E030A3Q005465787442752Q746F6E02B81E85EB51B8DE3F03103Q004261636B67726F756E64436F6C6F723303053Q0070616E656C030F3Q00426F7264657253697A65506978656C03043Q00466F6E7403043Q00456E756D030A3Q00476F7468616D426F6C6403083Q005465787453697A65026Q002640030A3Q0054657874436F6C6F723303043Q007465787403043Q0054657874030C3Q0062746E5F612Q645F7A6F6E65030F3Q004175746F42752Q746F6E436F6C6F72026Q002040030C3Q007A6F6E65436C65617242746E03083Q00506F736974696F6E02A4703D0AD7A3E03F03043Q006361726403053Q006D75746564030F3Q0062746E5F636C6561725F7A6F6E657303123Q007A6F6E65734C697374436F6E7461696E6572030D3Q004175746F6D6174696353697A6503013Q0059030C3Q0055494C6973744C61796F757403073Q0050612Q64696E6703043Q005544696D03093Q00536F72744F7264657203113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E65637403123Q0072656275696C645A6F6E65734C697374554903073Q007365635F687562030F3Q00746F2Q676C655F6875625F77616974030E3Q0048756257616974456E61626C656403083Q007365635F73652Q6C030F3Q00746F2Q676C655F6175746F73652Q6C030F3Q004175746F53652Q6C456E61626C656403113Q00736C696465725F73652Q6C5F636865636B026Q003440026Q005E4003113Q0053652Q6C436865636B496E74657276616C030A3Q0073652Q6C42746E526F77030D3Q006D616E75616C53652Q6C42746E03063Q00612Q63656E7403023Q006267030C3Q0062746E5F73652Q6C5F6E6F77030A3Q0073652Q6C537461747573026Q00304003063Q00476F7468616D026Q002440030E3Q005465787458416C69676E6D656E7403043Q004C656674030D3Q00646973636F72645363726F2Q6C030B3Q00646973636F726457726170030A3Q00776562682Q6F6B426F78025Q00805240030C3Q00776562682Q6F6B5469746C65026Q0034C0026Q003240030D3Q00776562682Q6F6B5F7469746C65030C3Q00776562682Q6F6B496E70757403073Q0054657874426F78026Q002Q4003103Q00436C656172546578744F6E466F637573030F3Q00506C616365686F6C6465725465787403243Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F3Q2E03113Q00506C616365686F6C646572436F6C6F723303123Q0055736572446973636F7264576562682Q6F6B030D3Q00646973636F726453746174757303103Q0063616E557365436F6E66696746696C6503103Q00776562682Q6F6B5F73617665645F6F6B03113Q00776562682Q6F6B5F73617665645F626164030B3Q00646973636F72644F707473025Q00406A4003113Q00646973636F72644F7074734C61796F7574030A3Q00646973636F726450616403093Q00554950612Q64696E67030A3Q0050612Q64696E67546F70030D3Q0050612Q64696E67426F2Q746F6D030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E67526967687403163Q00746F2Q676C655F646973636F72645F7265706F72747303153Q00446973636F72645265706F727473456E61626C656403133Q00746F2Q676C655F646973636F72645F73746F7003103Q00446973636F72644C6F674F6E53746F7003133Q00746F2Q676C655F646973636F72645F73652Q6C03103Q00446973636F72644C6F674F6E53652Q6C030B3Q00696E74657276616C426F78026Q0020C0026Q004A4003173Q00736C696465725F646973636F72645F696E74657276616C03143Q00446973636F72645265706F72744D696E75746573030B3Q00646973636F726442746E7303073Q007465737442746E03103Q0062746E5F746573745F776562682Q6F6B03073Q007361766542746E03083Q0062746E5F7361766503153Q00612Q706C79576562682Q6F6B46726F6D496E70757403093Q00466F6375734C6F7374030D3Q004D6178694875624553504C696203063Q00747970656F6603083Q006275696C6454616203083Q0066756E6374696F6E03093Q00676574436F6E666967030D3Q006F6E4669656C644368616E676503183Q006275696C644D6178694875624368616E67656C6F6754616203163Q006275696C644D61786948756243726564697473546162030C3Q006F6E496E707574426567616E03083Q0066696E616C697A6503123Q00612Q706C794D6178694875624C6F63616C65030A3Q007265667265736845737003043Q007461736B03053Q00737061776E03173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q00612Q706C7952656E6465723364537461746503063Q0073696C656E7403083Q00736B69705361766503133Q0068617350656E64696E6753652Q6C5374617465031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F74737472617003053Q00646566657203153Q004D617869487562526567697374657252656A6F696E03053Q007063612Q6C00B1062Q00124A012Q00013Q00061E012Q000400013Q0004603Q000400012Q000C012Q00014Q006B012Q00013Q0012C53Q00013Q00124Q00028Q0001000100124Q00033Q00122Q000100053Q00104Q0004000100124Q00068Q0001000100124Q00078Q0001000100124Q00088Q0001000100124Q000A8Q0001000200124Q00093Q00124Q000C3Q00206Q000D4Q00013Q001400122Q0002000E3Q00102Q0001000E000200122Q0002000F3Q00102Q0001000F000200122Q000200033Q00102Q00010003000200122Q000200113Q00102Q00010010000200122Q000200033Q00202Q00020002000400062Q0002002900013Q0004603Q0029000100124A010200133Q00124A010300033Q0020480103000300042Q00790102000200020006490002002D000100010004603Q002D000100124A010200053Q0006490002002D000100010004603Q002D000100127C010200143Q0010322Q0100120002001225010200163Q00102Q00010015000200122Q000200183Q00102Q00010017000200122Q0002001A3Q00102Q00010019000200302Q0001001B001C00122Q0002001E3Q00122Q0003001F6Q0002000200020010322Q01001D000200124A0102001E3Q00127C010300214Q00790102000200020010322Q010020000200124A010200233Q0010322Q010022000200124A010200253Q0010322Q010024000200124A010200263Q0010322Q010026000200124A0102001E3Q001206010300286Q00020002000200102Q00010027000200122Q0002001E3Q00122Q0003002A6Q00020002000200102Q00010029000200023501025Q0010322Q01002B0002000235010200013Q0010322Q01002C000200124A010200093Q0010322Q01002D0002000235010200023Q0010322Q01002E000200124A010200303Q0010322Q01002F000200124A010200323Q0010322Q010031000200124A010200343Q0010322Q01003300022Q0079012Q0002000200123F012Q000B3Q00124Q000B3Q00206Q003500124Q00353Q00124Q000B3Q00206Q003600124Q00363Q00124Q000B3Q00206Q003700124Q00373Q00124A012Q000B3Q002048014Q003800123F012Q00383Q00124Q000B3Q00206Q003900124Q00393Q00124Q000B3Q00206Q003A00124Q003A3Q00124Q000B3Q00206Q003B00124Q003B3Q00124A012Q000B3Q002048014Q003C00123F012Q003C3Q00124Q000B3Q00206Q003D00124Q003D3Q00124Q000B3Q00206Q003E00124Q003E3Q00124Q000B3Q00206Q003F00124Q003F3Q00124A012Q000B3Q002048014Q004000128F3Q00403Q00124A012Q000B3Q002048014Q00410006493Q0084000100010004603Q00840001000235012Q00033Q00128F3Q00413Q00124A012Q000B3Q002048014Q004200128F3Q00423Q00124A012Q000B3Q002048014Q004300128F3Q00433Q00124A012Q000B3Q002048014Q004400128F3Q00443Q00124A012Q00423Q00128F3Q00453Q00124A012Q000B3Q002048014Q004300128F3Q00463Q000235012Q00043Q0012A63Q00479Q003Q00124Q00489Q003Q00124Q00499Q003Q00124Q004A3Q000235012Q00053Q002Q123Q004B3Q00124Q00363Q00206Q004D00124Q004C3Q00124Q003E3Q00122Q0001004C3Q00122Q0002001E3Q00122Q0003004F6Q00020002000200122Q000300503Q00202Q00030003005100122Q000400523Q00122Q000500533Q00122Q000600536Q000700073Q00122Q0008004F8Q0008000200124Q004E3Q00124Q00403Q00122Q0001004E3Q00122Q0002001E3Q00122Q000300546Q00020002000200122Q000300553Q000235010400063Q00129B0105004D3Q00122Q000600563Q00122Q000700548Q0007000100124Q00403Q00122Q0001004E3Q00122Q0002001E3Q00122Q000300576Q0002000200024Q00035Q000235010400073Q0012EE000500583Q00122Q000600593Q00122Q000700578Q0007000200124Q00493Q00124Q00403Q00122Q0001004E3Q00122Q0002001E3Q00122Q0003005A6Q00020002000200124A0103005B3Q000235010400083Q0012A30105005C3Q00122Q0006005D3Q00122Q0007005A8Q0007000100124Q003E3Q00122Q0001004C3Q00122Q0002001E3Q00122Q0003005F6Q00020002000200122Q000300503Q00204801030003005100124A010400503Q00204801040004006000124A010500503Q00204801050005006100127C010600533Q00124A010700503Q00204801070007006200127C0108005F4Q00DD3Q0008000200128F3Q005E3Q00124A012Q004A3Q00124A2Q01003F3Q00124A0102005E3Q00124A0103001E3Q001298000400646Q00030002000200122Q0004004D3Q00122Q000500646Q00010005000200104Q0063000100124Q004A3Q00122Q0001003F3Q00122Q0002005E3Q00122Q0003001E3Q001298000400666Q00030002000200122Q000400583Q00122Q000500666Q00010005000200104Q0065000100124Q004A3Q00122Q0001003F3Q00122Q0002005E3Q00122Q0003001E3Q001298000400686Q00030002000200122Q0004005C3Q00122Q000500686Q00010005000200104Q0067000100124Q004A3Q00122Q0001003F3Q00122Q0002005E3Q00122Q0003001E3Q0012980004006A6Q00030002000200122Q0004006B3Q00122Q0005006A6Q00010005000200104Q0069000100124Q004A3Q00122Q0001003F3Q00122Q0002005E3Q00122Q0003001E3Q0012980004006D6Q00030002000200122Q0004006E3Q00122Q0005006D6Q00010005000200104Q006C000100124Q004A3Q00122Q0001003F3Q00122Q0002005E3Q00122Q0003001E3Q00127C010400704Q007901030002000200127C010400713Q00127C010500704Q00DD000100050002001032012Q006F000100124A012Q003E3Q00124A2Q01004C3Q00124A0102001E3Q00127C010300734Q007901020002000200124A010300503Q00204801030003007400124A010400503Q00204801040004007500127C010500533Q00124A010600503Q00204801060006007600124A010700503Q00204801070007007700127C010800734Q00DD3Q0008000200128F3Q00723Q00124A012Q003B3Q0012032Q0100723Q00122Q000200533Q00122Q0003001E3Q00122Q000400786Q00030002000200122Q000400533Q00122Q000500793Q00122Q0006007A3Q000235010700093Q001266010800788Q0008000100124Q003B3Q00122Q000100723Q00122Q000200503Q00202Q00020002007B00122Q0003001E3Q00122Q0004007C6Q00030002000200122Q000400533Q00127C010500793Q00124A0106007D3Q0002350107000A3Q00127C0108007C4Q0068012Q0008000100124A012Q007F3Q002048014Q008000127C2Q0100814Q0079012Q0002000200128F3Q007E3Q00124A012Q007E3Q00124A2Q0100833Q0020732Q010001008000122Q0002004D3Q00122Q000300533Q00122Q000400533Q00122Q000500536Q000100050002001032012Q0082000100124A012Q007E3Q00309F012Q0084008500124A012Q007E3Q00124A2Q01004C3Q001032012Q0086000100124A012Q003C3Q00124A2Q0100363Q0020482Q01000100582Q0079012Q0002000200128F3Q00873Q00124A012Q003D3Q00124A2Q0100874Q0079012Q0002000200128F3Q00883Q00124A012Q00883Q002024014Q008900127C0102008A4Q006B010300014Q0068012Q0003000100127C012Q00533Q0006880001000B000100012Q00F07Q00121D010200393Q00122Q000300883Q00122Q0004001E3Q00122Q0005008B6Q0004000200024Q000500016Q00050001000200122Q0006008B6Q00020006000100122Q000200403Q00124A010300883Q00124A0104001E3Q00127C0105008C4Q007901040002000200124A0105008D3Q0002350106000C4Q00F0000700014Q00B500070001000200127C010800563Q0012700009008C6Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q0005008E6Q00040002000200122Q0005008F3Q0002350106000D4Q00A9010700016Q00070001000200122Q000800593Q00122Q0009008E6Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500906Q00040002000200122Q000500913Q00262Q000500952Q0100920004603Q00952Q012Q007100056Q006B010500013Q0002350106000E4Q005C000700016Q0007000100024Q000800083Q00122Q000900906Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500936Q00040002000200122Q000500913Q00262Q000500A52Q0100940004603Q00A52Q012Q007100056Q006B010500013Q0002350106000F4Q0025000700016Q0007000100024Q000800083Q00122Q000900936Q00020009000100122Q000200393Q00122Q000300883Q00122Q0004001E3Q00122Q000500956Q0004000200024Q000500016Q00050001000200122Q000600956Q00020006000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500966Q00040002000200122Q000500973Q00262Q000500BE2Q0100980004603Q00BE2Q012Q007100056Q006B010500013Q000235010600104Q008E000700016Q0007000100024Q000800083Q00122Q000900966Q00020009000100122Q000200413Q00122Q000300883Q00122Q0004001E3Q00122Q000500996Q00040002000200122Q000500583Q00122Q0006009A3Q00122Q0007009B3Q000235010800114Q001F010900016Q00090001000200122Q000A00996Q0002000A000100122Q000200413Q00122Q000300883Q00122Q0004001E3Q00122Q0005009C6Q00040002000200122Q0005009D3Q00122Q0006009E3Q00122Q0007009F3Q000235010800124Q001F010900016Q00090001000200122Q000A009C6Q0002000A000100122Q000200413Q00122Q000300883Q00122Q0004001E3Q00122Q000500A06Q00040002000200122Q000500533Q00122Q000600A13Q00122Q000700A23Q000235010800134Q00BE000900016Q00090001000200122Q000A00A06Q0002000A000100122Q000200393Q00122Q000300883Q00122Q0004001E3Q00122Q000500A36Q0004000200024Q000500014Q00B5000500010002001270000600A36Q00020006000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500A46Q00040002000200122Q000500A53Q000235010600144Q0056010700016Q0007000100024Q000800083Q00122Q000900A46Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500A66Q00040002000200122Q000500A73Q000235010600154Q0056010700016Q0007000100024Q000800083Q00122Q000900A66Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500A86Q00040002000200122Q000500A93Q000235010600164Q0056010700016Q0007000100024Q000800083Q00122Q000900A86Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500AA6Q00040002000200122Q000500AB3Q000235010600174Q0056010700016Q0007000100024Q000800083Q00122Q000900AA6Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500AC6Q00040002000200122Q000500AD3Q000235010600184Q008E000700016Q0007000100024Q000800083Q00122Q000900AC6Q00020009000100122Q000200413Q00122Q000300883Q00122Q0004001E3Q00122Q000500AE6Q00040002000200122Q0005009E3Q00122Q0006005C3Q00122Q000700AF3Q000235010800194Q001F010900016Q00090001000200122Q000A00AE6Q0002000A000100122Q000200413Q00122Q000300883Q00122Q0004001E3Q00122Q000500B06Q00040002000200122Q0005006B3Q00122Q000600B13Q00122Q000700B23Q0002350108001A4Q00BE000900016Q00090001000200122Q000A00B06Q0002000A000100122Q000200393Q00122Q000300883Q00122Q0004001E3Q00122Q000500B36Q0004000200024Q000500014Q00B5000500010002001270000600B36Q00020006000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500B56Q00040002000200122Q000500B63Q0002350106001B4Q00B2000700016Q0007000100024Q000800083Q00122Q000900B56Q00020009000200122Q000200B43Q00122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500B76Q00040002000200122Q000500B83Q0002350106001C4Q0056010700016Q0007000100024Q000800083Q00122Q000900B76Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500B96Q00040002000200122Q000500BA3Q0002350106001D4Q008A010700016Q0007000100024Q000800083Q00122Q000900B96Q00020009000100122Q000200393Q00122Q000300883Q00122Q0004001E3Q00122Q000500BB6Q0004000200024Q000500016Q00050001000200122Q000600BB6Q00020006000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500BC6Q00040002000200122Q000500BD3Q0002350106001E4Q0056010700016Q0007000100024Q000800083Q00122Q000900BC6Q00020009000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500BE6Q00040002000200122Q000500BF3Q0002350106001F4Q008A010700016Q0007000100024Q000800083Q00122Q000900BE6Q00020009000100122Q000200393Q00122Q000300883Q00122Q0004001E3Q00122Q000500C06Q0004000200024Q000500016Q00050001000200122Q000600C06Q00020006000100122Q000200403Q00122Q000300883Q00122Q0004001E3Q00122Q000500C16Q00040002000200122Q000500C23Q000235010600204Q00D5000700016Q0007000100024Q000800083Q00122Q000900C16Q00020009000100122Q0002007F3Q00202Q00020002008000122Q000300C46Q00020002000200122Q000200C33Q00122Q000200C33Q00122Q000300833Q00202Q00030003008000122Q0004004D3Q00122Q000500533Q00122Q000600533Q00122Q000700C56Q00030007000200102Q00020082000300122Q000200C33Q00302Q000200C6004D00122Q000200C36Q000300016Q00030001000200102Q000200C7000300122Q000200C33Q00122Q000300883Q00102Q00020086000300122Q0002007F3Q00202Q00020002008000122Q000300C96Q00020002000200122Q000200C83Q00122Q000200C83Q00122Q000300833Q00202Q00030003008000122Q000400CA3Q00122Q000500533Q00122Q0006004D3Q00122Q000700536Q00030007000200102Q00020082000300122Q000200C83Q00122Q000300353Q00202Q0003000300CC00102Q000200CB000300122Q000200C83Q00302Q000200CD005300122Q000200C83Q00122Q000300CF3Q00202Q0003000300CE00202Q0003000300D000102Q000200CE000300122Q000200C83Q00302Q000200D100D200122Q000200C83Q00122Q000300353Q00202Q0003000300D400102Q000200D3000300122Q000200C83Q00122Q0003001E3Q00122Q000400D66Q00030002000200102Q000200D5000300122Q000200C83Q00302Q000200D7008500122Q000200C83Q00122Q000300C33Q00102Q00020086000300122Q000200373Q00122Q000300C83Q00122Q000400D86Q00020004000100122Q000200263Q00122Q000300C83Q00122Q000400D66Q00020004000100122Q0002007F3Q00202Q00020002008000122Q000300C94Q00790102000200020012CF000200D93Q00122Q000200D93Q00122Q000300833Q00202Q00030003008000122Q000400CA3Q00122Q000500533Q00122Q0006004D3Q00122Q000700536Q00030007000200102Q00020082000300122Q000200D93Q00122Q000300833Q00202Q00030003008000122Q000400DB3Q00122Q000500533Q00122Q000600533Q00122Q000700536Q00030007000200102Q000200DA000300122Q000200D93Q00122Q000300353Q00202Q0003000300DC00102Q000200CB000300122Q000200D93Q00302Q000200CD005300122Q000200D93Q00122Q000300CF3Q00202Q0003000300CE00202Q0003000300D000102Q000200CE000300122Q000200D93Q00302Q000200D100D200122Q000200D93Q00122Q000300353Q00202Q0003000300DD00102Q000200D3000300122Q000200D93Q00122Q0003001E3Q00122Q000400DE6Q00030002000200102Q000200D5000300122Q000200D93Q00302Q000200D7008500122Q000200D93Q00122Q000300C33Q00102Q00020086000300122Q000200373Q00122Q000300D93Q00122Q000400D86Q00020004000100122Q000200263Q00122Q000300D93Q00122Q000400DE6Q00020004000100122Q0002007F3Q00202Q00020002008000122Q000300C46Q00020002000200122Q000200DF3Q00122Q000200DF3Q00122Q000300833Q00202Q00030003008000122Q0004004D3Q00122Q000500533Q00122Q000600533Q00122Q000700536Q00030007000200102Q00020082000300122Q000200DF3Q00122Q000300CF3Q00202Q0003000300E000202Q0003000300E100102Q000200E0000300122Q000200DF3Q00302Q000200C6004D00122Q000200DF6Q000300016Q00030001000200102Q000200C7000300122Q000200DF3Q00124A010300883Q0010320102008600030012370002007F3Q00202Q00020002008000122Q000300E26Q00020002000200122Q000300E43Q00204801030003008000127C010400533Q00127C010500D84Q00DD000300050002001032010200E3000300124A010300CF3Q0020480103000300E50020480103000300C7001032010200E5000300124A010300DF3Q00103201020086000300124A010300C83Q0020480103000300E60020240103000300E7000235010500214Q006801030005000100124A010300D93Q0020480103000300E60020240103000300E7000235010500224Q00EF00030005000100122Q000300E86Q00030001000100122Q000300393Q00122Q000400883Q00122Q0005001E3Q00122Q000600E96Q0005000200024Q000600016Q00060001000200122Q000700E96Q00030007000100122Q000300403Q00122Q000400883Q00122Q0005001E3Q00122Q000600EA6Q00050002000200122Q000600EB3Q000235010700234Q008A010800016Q0008000100024Q000900093Q00122Q000A00EA6Q0003000A000100122Q000300393Q00122Q000400883Q00122Q0005001E3Q00122Q000600EC6Q0005000200024Q000600016Q00060001000200122Q000700EC6Q00030007000100122Q000300403Q00122Q000400883Q00122Q0005001E3Q00122Q000600ED6Q00050002000200122Q000600EE3Q000235010700244Q008E000800016Q0008000100024Q000900093Q00122Q000A00ED6Q0003000A000100122Q000300413Q00122Q000400883Q00122Q0005001E3Q00122Q000600EF6Q00050002000200122Q000600F03Q00122Q000700F13Q00122Q000800F23Q000235010900254Q0052010A00016Q000A0001000200122Q000B00EF6Q0003000B000100122Q0003007F3Q00202Q00030003008000122Q000400C46Q00030002000200122Q000300F33Q00122Q000300F33Q00124A010400833Q00207301040004008000122Q0005004D3Q00122Q000600533Q00122Q000700533Q00122Q000800C56Q00040008000200107200030082000400122Q000300F33Q00302Q000300C6004D00122Q000300F36Q000400016Q00040001000200102Q000300C7000400122Q000300F33Q00122Q000400883Q00102Q00030086000400124A0103007F3Q00204801030003008000127C010400C94Q007901030002000200128F000300F43Q00124A010300F43Q00124A010400833Q00207301040004008000122Q0005004D3Q00122Q000600533Q00122Q0007004D3Q00122Q000800536Q000400080002002Q1000030082000400122Q000300F43Q00122Q000400353Q00202Q0004000400F500102Q000300CB000400122Q000300F43Q00302Q000300CD005300122Q000300F43Q00122Q000400CF3Q00202Q0004000400CE0020480104000400D000102E010300CE000400122Q000300F43Q00302Q000300D100D200122Q000300F43Q00122Q000400353Q00202Q0004000400F600102Q000300D3000400122Q000300F43Q00122Q0004001E3Q00122Q000500F74Q0079010400020002001032010300D5000400124A010300F43Q00309F010300D7008500124A010300F43Q00124A010400F33Q00103201030086000400124A010300373Q00124A010400F43Q0012A6010500D86Q00030005000100122Q000300263Q00122Q000400F43Q00122Q000500F76Q00030005000100124A0103007F3Q00204801030003008000127C010400814Q007901030002000200128F000300F83Q00124A010300F83Q00124A010400833Q00207301040004008000122Q0005004D3Q00122Q000600533Q00122Q000700533Q00122Q000800F96Q00040008000200105501030082000400122Q000300F83Q00302Q000300C6004D00122Q000300F83Q00122Q000400CF3Q00202Q0004000400CE00202Q0004000400FA00102Q000300CE000400122Q000300F83Q00302Q000300D100FB00124A010300F83Q001236000400353Q00202Q0004000400DD00102Q000300D3000400122Q000300F83Q00122Q000400CF3Q00202Q0004000400FC00202Q0004000400FD00102Q000300FC000400122Q000300F83Q00302Q000300D5001400124A010300F84Q00D8000400016Q00040001000200102Q000300C7000400122Q000300F83Q00122Q000400883Q00102Q00030086000400122Q000300F43Q00202Q0003000300E600202Q0003000300E7000235010500264Q00FF00030005000100122Q0003003C3Q00122Q000400363Q00202Q00040004005C4Q00030002000200122Q000300FE3Q00122Q0003003D3Q00122Q000400FE6Q00030002000200122Q000300FF3Q00122Q0003007F3Q00202Q00030003008000122Q000400C46Q00030002000200122Q00032Q00012Q00122Q00032Q00012Q00122Q000400833Q00202Q00040004008000122Q0005004D3Q00122Q000600533Q00122Q000700533Q00122Q0008002Q015Q00040008000200102Q00030082000400122Q00032Q00012Q00122Q000400353Q00202Q0004000400DC00102Q000300CB000400122Q00032Q00012Q00122Q000400533Q00102Q000300CD000400122Q00032Q00012Q00122Q0004004D3Q00102Q000300C7000400122Q00032Q00012Q00122Q000400FF3Q00102Q00030086000400122Q000300373Q00122Q00042Q00012Q00122Q000500FB6Q00030005000100122Q0003007F3Q00202Q00030003008000122Q000400816Q00030002000200122Q00030002012Q00122Q00030002012Q00122Q000400833Q00202Q00040004008000122Q0005004D3Q00122Q00060003012Q00122Q000700533Q00122Q00080004015Q00040008000200102Q00030082000400122Q00030002012Q00122Q000400833Q00202Q00040004008000122Q000500533Q00122Q000600FB3Q00122Q000700533Q00122Q000800D86Q00040008000200102Q000300DA000400122Q00030002012Q00122Q0004004D3Q00102Q000300C6000400122Q00030002012Q00122Q000400CF3Q00202Q0004000400CE00202Q0004000400D000102Q000300CE000400122Q00030002012Q00122Q000400D23Q00102Q000300D1000400122Q00030002012Q00122Q000400353Q00202Q0004000400D400102Q000300D3000400122Q00030002012Q00124A010400CF3Q0020B70004000400FC00202Q0004000400FD00102Q000300FC000400122Q00030002012Q00122Q0004001E3Q00122Q00050005015Q00040002000200102Q000300D5000400122Q00030002012Q00122Q00042Q00012Q00102Q00030086000400122Q000300263Q00122Q00040002012Q00122Q00050005015Q00030005000100122Q0003007F3Q00202Q00030003008000122Q00040007015Q00030002000200122Q00030006012Q00122Q00030006012Q00122Q000400833Q00202Q00040004008000122Q0005004D3Q00122Q00060003012Q00122Q000700533Q00122Q000800B16Q00040008000200102Q00030082000400122Q00030006012Q00122Q000400833Q00202Q00040004008000122Q000500533Q00122Q000600FB3Q00122Q000700533Q00122Q00080008015Q00040008000200102Q000300DA000400122Q00030006012Q00122Q000400353Q00202Q0004000400CC00102Q000300CB000400122Q00030006012Q00122Q000400533Q00102Q000300CD000400122Q00030006012Q00122Q00040009015Q00058Q00030004000500122Q00030006012Q00122Q000400CF3Q00202Q0004000400CE00202Q0004000400FA00102Q000300CE000400122Q00030006012Q00122Q000400FB3Q00102Q000300D1000400122Q00030006012Q00122Q000400353Q00202Q0004000400D400102Q000300D3000400122Q00030006012Q00122Q0004000A012Q00122Q0005000B015Q00030004000500122Q00030006012Q00122Q0004000C012Q00122Q000500353Q00202Q0005000500DD4Q00030004000500122Q00030006012Q00122Q0004000D012Q00102Q000300D5000400122Q00030006012Q00122Q000400CF3Q00202Q0004000400FC00202Q0004000400FD00102Q000300FC000400122Q00030006012Q00122Q00042Q00012Q001032010300860004001202010300373Q00122Q00040006012Q00122Q000500D86Q00030005000100122Q0003007F3Q00202Q00030003008000122Q000400816Q00030002000200122Q0003000E012Q00122Q0003000E012Q00122Q000400833Q00202Q00040004008000122Q0005004D3Q00122Q000600533Q00122Q000700533Q00122Q000800F96Q00040008000200102Q00030082000400122Q0003000E012Q00122Q0004004D3Q00102Q000300C6000400122Q0003000E012Q00122Q000400CF3Q00202Q0004000400CE00202Q0004000400FA00102Q000300CE000400122Q0003000E012Q00122Q000400FB3Q00102Q000300D1000400122Q0003000E012Q00122Q000400353Q00202Q0004000400DD00102Q000300D3000400122Q0003000E012Q00122Q000400CF3Q00202Q0004000400FC00202Q0004000400FD00102Q000300FC000400122Q0003000E012Q00122Q0004000F015Q00040001000200062Q000400E704013Q0004603Q00E7040100124A0104001E3Q00127C01050010013Q0079010400020002000649000400EA040100010004603Q00EA040100124A0104001E3Q00127C01050011013Q0079010400020002001032010300D5000400124A0103000E012Q00127C010400583Q001032010300C7000400124A0103000E012Q00124A010400FF3Q00103201030086000400124A0103007F3Q00204801030003008000127C010400C44Q007901030002000200128F00030012012Q00124A01030012012Q00124A010400833Q00207301040004008000122Q0005004D3Q00122Q000600533Q00122Q000700533Q00122Q00080013015Q00040008000200100701030082000400122Q00030012012Q00122Q000400353Q00202Q0004000400DC00102Q000300CB000400122Q00030012012Q00122Q000400533Q00102Q000300CD000400122Q00030012012Q00122Q0004005C3Q001032010300C7000400124A01030012012Q00124A010400FF3Q00103201030086000400124A010300373Q00124E00040012012Q00122Q000500FB6Q00030005000100122Q0003007F3Q00202Q00030003008000122Q000400E26Q00030002000200122Q00030014012Q00122Q00030014012Q00122Q000400E43Q00204801040004008000127C010500533Q00127C0106006B4Q00DD000400060002001032010300E3000400124A01030014012Q00124A010400CF3Q0020480104000400E50020210004000400C700102Q000300E5000400122Q00030014012Q00122Q00040012012Q00102Q00030086000400122Q0003007F3Q00202Q00030003008000122Q00040016015Q00030002000200122Q00030015012Q00124A01030015012Q0012C600040017012Q00122Q000500E43Q00202Q00050005008000122Q000600533Q00122Q000700D86Q0005000700024Q00030004000500122Q00030015012Q00122Q00040018012Q00122Q000500E43Q002048010500050080001239000600533Q00122Q000700D86Q0005000700024Q00030004000500122Q00030015012Q00122Q00040019012Q00122Q000500E43Q00200100050005008000122Q000600533Q00122Q0007006B6Q0005000700024Q00030004000500122Q00030015012Q00122Q0004001A012Q00122Q000500E43Q00202Q00050005008000122Q000600533Q00122Q0007006B6Q0005000700024Q00030004000500122Q00030015012Q00122Q00040012012Q00102Q00030086000400122Q000300403Q00122Q00040012012Q00122Q0005001E3Q00122Q0006001B015Q00050002000200122Q0006001C012Q000235010700273Q0012A30108004D3Q00122Q000900563Q00122Q000A001B015Q0003000A000100122Q000300403Q00122Q00040012012Q00122Q0005001E3Q00122Q0006001D015Q00050002000200122Q0006001E012Q000235010700283Q0012A3010800583Q00122Q000900593Q00122Q000A001D015Q0003000A000100122Q000300403Q00122Q00040012012Q00122Q0005001E3Q00122Q0006001F015Q00050002000200122Q00060020012Q000235010700293Q0012F70008005C3Q00122Q0009005D3Q00122Q000A001F015Q0003000A000100122Q0003007F3Q00202Q00030003008000122Q000400C46Q00030002000200122Q00030021012Q00122Q00030021012Q00122Q000400833Q00202Q00040004008000122Q0005004D3Q00122Q00060022012Q00122Q000700533Q00122Q00080023015Q00040008000200102Q00030082000400122Q00030021012Q00122Q0004004D3Q00102Q000300C6000400122Q00030021012Q00122Q0004006B3Q00102Q000300C7000400122Q00030021012Q00122Q00040012012Q00102Q00030086000400122Q0003003B3Q00122Q00040021012Q00122Q000500533Q00122Q0006001E3Q00122Q00070024015Q00060002000200122Q0007004D3Q00122Q000800F13Q00122Q00090025012Q000235010A002A3Q00124C010B0024015Q0003000B000100122Q0003007F3Q00202Q00030003008000122Q000400C46Q00030002000200122Q00030026012Q00122Q00030026012Q00122Q000400833Q00202Q00040004008000122Q0005004D3Q00122Q000600533Q00122Q000700533Q00122Q000800C56Q00040008000200102Q00030082000400122Q00030026012Q00122Q0004004D3Q00102Q000300C6000400122Q00030026012Q00122Q0004006E3Q00102Q000300C7000400122Q00030026012Q00122Q000400FF3Q00102Q00030086000400122Q0003007F3Q00202Q00030003008000122Q000400C96Q00030002000200122Q00030027012Q00122Q00030027012Q00122Q000400833Q00202Q00040004008000122Q000500CA3Q00122Q000600533Q00122Q0007004D3Q00122Q000800536Q00040008000200102Q00030082000400122Q00030027012Q00122Q000400353Q00202Q0004000400F500102Q000300CB000400122Q00030027012Q00122Q000400533Q00102Q000300CD000400122Q00030027012Q00122Q000400CF3Q00202Q0004000400CE00202Q0004000400D000102Q000300CE000400122Q00030027012Q00122Q000400D23Q00102Q000300D1000400122Q00030027012Q00122Q000400353Q00202Q0004000400F600102Q000300D3000400122Q00030027012Q00122Q0004001E3Q00122Q00050028015Q00040002000200102Q000300D5000400122Q00030027015Q00045Q00102Q000300D7000400122Q00030027012Q00122Q00040026012Q00102Q00030086000400122Q000300373Q00122Q00040027012Q00122Q000500D86Q00030005000100122Q000300263Q00122Q00040027012Q00122Q00050028015Q00030005000100122Q0003007F3Q00202Q00030003008000122Q000400C94Q007901030002000200128F00030029012Q00124A01030029012Q00124A010400833Q00207301040004008000122Q000500CA3Q00122Q000600533Q00122Q0007004D3Q00122Q000800536Q00040008000200103201030082000400124A01030029012Q00124A010400833Q00207301040004008000122Q000500DB3Q00122Q000600533Q00122Q000700533Q00122Q000800536Q000400080002001032010300DA000400124A01030029012Q00124A010400353Q0020480104000400CC001032010300CB000400124A01030029012Q00127C010400533Q001032010300CD000400124A01030029012Q00124A010400CF3Q0020480104000400CE0020480104000400D0001032010300CE000400124A01030029012Q00127C010400D23Q001032010300D1000400124A01030029012Q00124A010400353Q0020480104000400D4001032010300D3000400124A01030029012Q00124A0104001E3Q00127C0105002A013Q0079010400020002001032010300D5000400124A01030029013Q006B01045Q001032010300D7000400124A01030029012Q00124A01040026012Q00103201030086000400124A010300373Q00124A01040029012Q0012A6010500D86Q00030005000100122Q000300263Q00122Q00040029012Q00122Q0005002A015Q0003000500010002350103002B3Q0012D90003002B012Q00122Q00030006012Q00122Q0004002C015Q00030003000400202Q0003000300E70002350105002C4Q006801030005000100124A01030029012Q0020480103000300E60020240103000300E70002350105002D4Q006801030005000100124A01030027012Q0020480103000300E60020240103000300E70002350105002E4Q006801030005000100124A0103002D012Q00061E0103005706013Q0004603Q0057060100124A0103002E012Q0012940104002D012Q00122Q0005002F015Q0004000400054Q00030002000200122Q00040030012Q00062Q00030057060100040004603Q0057060100124A0103002D012Q0012610004002F015Q00030003000400122Q000400363Q00122Q0005006B6Q0004000400054Q00053Q000C00122Q000600353Q00102Q00050035000600122Q0006003C3Q00102Q0005003C000600124A0106003D3Q00100D0005003D000600122Q000600373Q00102Q00050037000600122Q000600393Q00102Q00050039000600122Q000600403Q00102Q00050040000600122Q000600413Q00102Q00050041000600122Q0006003B3Q0010320105003B000600124A0106001E3Q0010320105001E000600124A010600263Q00103201050026000600127C01060031012Q0002350107002F4Q008401050006000700127C01060032012Q000235010700304Q00840105000600072Q006801030005000100124A01030033012Q0012A2010400363Q00122Q0005006E6Q0004000400054Q00053Q000400122Q000600353Q00102Q00050035000600122Q0006003C3Q00102Q0005003C000600122Q0006003D3Q00102Q0005003D000600122Q000600373Q00102Q0005003700064Q00030005000100122Q00030034012Q00122Q000400363Q00122Q000500716Q0004000400054Q00053Q000400122Q000600353Q00102Q00050035000600122Q0006003C3Q00102Q0005003C000600122Q0006003D3Q00102Q0005003D000600122Q000600373Q00102Q0005003700064Q00030005000100122Q0003000B3Q00122Q00040035015Q000300030004000235010400314Q004B01030002000100122Q0003000B3Q00122Q00040036015Q0003000300044Q00030001000100122Q00030037015Q00030001000100122Q00030038015Q00030001000100122Q00030039012Q00122Q0004003A015Q000300030004000235010400324Q009300030002000100122Q0003003B015Q00030001000100122Q0003003C012Q00122Q000400B66Q00053Q000200122Q0006003D015Q000700016Q00050006000700122Q0006003E013Q006B010700014Q00840105000600072Q006801030005000100124A0103003F013Q00B500030001000200061E0103009806013Q0004603Q0098060100124A01030040013Q00280103000100010004603Q00A0060100124A010300553Q00061E010300A006013Q0004603Q00A0060100124A01030039012Q00127C01040041013Q000A000300030004000235010400334Q00E300030002000100124A0103005B3Q00061E010300B006013Q0004603Q00B0060100124A0103002E012Q001294010400033Q00122Q00050042015Q0004000400054Q00030002000200122Q00040030012Q00062Q000300B0060100040004603Q00B0060100124A01030043012Q00124A010400033Q00127C01050042013Q000A0004000400052Q00E30003000200012Q000C012Q00013Q00343Q00013Q00030C3Q007365744661726D537461746500043Q00124A012Q00014Q006B2Q016Q00E33Q000200012Q000C012Q00017Q00023Q0003063Q007569522Q6F7403073Q0056697369626C6500093Q00124A012Q00013Q00061E012Q000800013Q0004603Q0008000100124A012Q00013Q00124A2Q0100013Q0020482Q01000100022Q00C4000100013Q001032012Q000200012Q000C012Q00017Q00073Q0003043Q0067656E76030E3Q004D6178694875624B65794761746503063Q00747970656F6603103Q006765744B65795374617475735465787403083Q0066756E6374696F6E03013Q004C030A3Q006B65795F756E7061696400163Q00124A012Q00013Q002048014Q000200061E012Q001100013Q0004603Q0011000100124A2Q0100033Q00204801023Q00042Q00792Q01000200020026A000010011000100050004603Q001100010020482Q013Q00042Q00B500010001000200064900010010000100010004603Q0010000100124A2Q0100063Q00127C010200074Q00792Q01000200022Q005C2Q0100023Q00124A2Q0100063Q00127C010200074Q00512Q0100024Q00C700016Q000C012Q00017Q000C3Q0003083Q00496E7374616E63652Q033Q006E657703053Q004672616D6503043Q0053697A6503053Q005544696D32026Q00F03F028Q00026Q004A4003163Q004261636B67726F756E645472616E73706172656E6379030B3Q004C61796F75744F7264657203063Q00506172656E74030A3Q006D616B65536C69646572081E3Q001286010800013Q00202Q00080008000200122Q000900036Q00080002000200122Q000900053Q00202Q00090009000200122Q000A00063Q00122Q000B00073Q00122Q000C00073Q00122Q000D00086Q0009000D000200102Q00080004000900302Q00080009000600062Q00090010000100060004603Q0010000100127C010900073Q0010320108000A00090010A30008000B3Q00122Q0009000C6Q000A00083Q00122Q000B00076Q000C00016Q000D00026Q000E00036Q000F00046Q001000056Q001100076Q0009001100014Q000800028Q00017Q00093Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D6174030B3Q002564D0BC2025303264D18103023Q00D18100153Q0012A43Q00018Q0001000200122Q000100023Q00202Q00010001000300202Q00023Q00044Q00010002000200202Q00023Q0004000E2Q00050010000100010004603Q0010000100124A010300063Q00207600030003000700122Q000400086Q000500016Q000600026Q000300066Q00036Q00F000035Q00127C010400094Q000B0103000300042Q005C010300024Q000C012Q00017Q000D3Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D03113Q0073652Q73696F6E54722Q65734D696E6564028Q0003123Q0073652Q73696F6E53746F6E65734D696E6564030E3Q006765744661726D5365636F6E6473026Q00344003083Q0073746F704661726D03103Q00446973636F72644C6F674F6E53746F7003043Q007461736B03053Q00646566657201353Q00061E012Q001100013Q0004603Q0011000100124A2Q0100013Q00061E2Q01000600013Q0004603Q000600012Q000C012Q00014Q006B2Q0100013Q0012302Q0100023Q00122Q000100036Q000200016Q000300016Q0001000300014Q00015Q00122Q000100023Q00122Q000100046Q00010001000100044Q0034000100124A2Q0100013Q00064900010015000100010004603Q001500012Q000C012Q00013Q00124A2Q0100053Q000E1700060020000100010004603Q0020000100124A2Q0100073Q000E1700060020000100010004603Q0020000100124A2Q0100084Q00B5000100010002000E1700090020000100010004603Q002000012Q007100016Q006B2Q0100014Q00BA000200013Q00122Q000200023Q00122Q000200036Q00038Q000400016Q0002000400014Q00025Q00122Q000200023Q00122Q0002000A6Q00020001000100062Q0001003400013Q0004603Q0034000100124A0102000B3Q00061E0102003400013Q0004603Q0034000100124A0102000C3Q00204801020002000D00023501036Q00E30002000200012Q000C012Q00013Q00013Q00013Q0003053Q007063612Q6C00043Q00124A012Q00013Q0002352Q016Q00E33Q000200012Q000C012Q00013Q00013Q00033Q0003153Q006C6F674661726D53652Q73696F6E446973636F7264031D3Q00D0A4D0B0D180D0BC20D0BED181D182D0B0D0BDD0BED0B2D0BBD0B5D0BD023Q008087E96C4100053Q0012CC3Q00013Q00122Q000100023Q00122Q000200038Q000200016Q00017Q00023Q00030D3Q004175746F53746172744661726D03123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q0003103Q006661726D546F2Q676C6553696C656E74030C3Q007365744661726D537461746501083Q00124A2Q0100013Q00061E2Q01000400013Q0004603Q000400012Q000C012Q00013Q00124A2Q0100024Q00F000026Q00E30001000200012Q000C012Q00017Q00073Q00030E3Q0052656A6F696E4175746F4C6F616403123Q007363686564756C6553617665436F6E66696703063Q00747970656F6603043Q0067656E7603153Q004D617869487562526567697374657252656A6F696E03083Q0066756E6374696F6E03053Q007063612Q6C01103Q00128F3Q00013Q00124A2Q0100024Q00282Q010001000100061E012Q000F00013Q0004603Q000F000100124A2Q0100033Q00124A010200043Q0020480102000200052Q00792Q01000200020026A00001000F000100060004603Q000F000100124A2Q0100073Q00124A010200043Q0020480102000200052Q00E30001000200012Q000C012Q00017Q00023Q00030E3Q0054656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q0003133Q0053746F6E6554656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00013Q00026Q00F03F00064Q0042016Q00206Q00019Q009Q006Q00028Q00017Q00023Q0003103Q004661726D54722Q6573456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q0003113Q004661726D53746F6E6573456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00033Q00030E3Q005461726765745069636B4D6F646503073Q006E65617265737403123Q007363686564756C6553617665436F6E66696701073Q00061E012Q000600013Q0004603Q0006000100127C2Q0100023Q00128F000100013Q00124A2Q0100034Q00282Q01000100012Q000C012Q00017Q00033Q00030E3Q005461726765745069636B4D6F646503063Q0072616E646F6D03123Q007363686564756C6553617665436F6E66696701073Q00061E012Q000600013Q0004603Q0006000100127C2Q0100023Q00128F000100013Q00124A2Q0100034Q00282Q01000100012Q000C012Q00017Q00043Q00030C3Q0054656C65706F72744D6F646503063Q00736D2Q6F746803073Q00696E7374616E7403123Q007363686564756C6553617665436F6E666967010A3Q00061E012Q000500013Q0004603Q0005000100127C2Q0100023Q00064900010006000100010004603Q0006000100127C2Q0100033Q00128F000100013Q00124A2Q0100044Q00282Q01000100012Q000C012Q00017Q00043Q0003103Q0054656C65706F72745374657053697A6503043Q006D61746803053Q00666C2Q6F7203123Q007363686564756C6553617665436F6E66696701083Q001216000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q0001000100016Q00017Q00023Q0003113Q0054656C65706F72745374657044656C617903123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q00030B3Q00412Q7461636B44656C617903123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q00030C3Q004F72626974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q00030B3Q0041696D417454617267657403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q0003073Q00557365464B657903123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00033Q0003083Q00557365436C69636B03103Q0072656C656173654D6F757365486F6C6403123Q007363686564756C6553617665436F6E66696701083Q00128F3Q00013Q00061E012Q000500013Q0004603Q0005000100124A2Q0100024Q00282Q010001000100124A2Q0100034Q00282Q01000100012Q000C012Q00017Q00033Q0003113Q004C656769744D6F7573654361707475726503103Q0072656C656173654D6F757365486F6C6403123Q007363686564756C6553617665436F6E66696701083Q00128F3Q00013Q0006493Q0005000100010004603Q0005000100124A2Q0100024Q00282Q010001000100124A2Q0100034Q00282Q01000100012Q000C012Q00017Q00023Q00030A3Q004F7262697453702Q656403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q00030D3Q004F726269744469616D6574657203123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q0003143Q0072656E6465723364546F2Q676C6553696C656E7403123Q00612Q706C7952656E6465723364537461746501083Q00124A2Q0100013Q00061E2Q01000400013Q0004603Q000400012Q000C012Q00013Q00124A2Q0100024Q00F000026Q00E30001000200012Q000C012Q00017Q00023Q0003123Q004175746F52656E64657233644F6E4661726D03123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00033Q0003123Q00426C61636B5363722Q656E4F7665726C617903183Q00757064617465426C61636B5363722Q656E4F7665726C617903123Q007363686564756C6553617665436F6E66696701063Q001282012Q00013Q00122Q000100026Q00010001000100122Q000100036Q0001000100016Q00017Q00023Q0003113Q00426C6F636B5569447572696E674661726D03123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00053Q00030B3Q00426C6F636B547261646573030B3Q004661726D456E61626C6564030A3Q007363616E54726164657303093Q00706C6179657247756903123Q007363686564756C6553617665436F6E666967010A3Q00128F3Q00013Q00124A2Q0100023Q00061E2Q01000700013Q0004603Q0007000100124A2Q0100033Q00124A010200044Q00E300010002000100124A2Q0100054Q00282Q01000100012Q000C012Q00017Q00033Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E66696701063Q001282012Q00013Q00122Q000100026Q00010001000100122Q000100036Q0001000100016Q00017Q00093Q0003163Q00736574426C6F636B65645A6F6E654174506C61796572030C3Q007A6F6E65506C61636542746E03043Q005465787403013Q004C030F3Q0062746E5F637562655F706C6163656403043Q007461736B03053Q0064656C6179026Q33F33F03103Q0062746E5F6E6F5F63686172616374657200153Q00124A012Q00014Q00B53Q0001000200061E012Q000F00013Q0004603Q000F000100124A012Q00023Q00124A2Q0100043Q00127C010200054Q00792Q0100020002001032012Q0003000100124A012Q00063Q002048014Q000700127C2Q0100083Q00023501026Q0068012Q000200010004603Q0014000100124A012Q00023Q00124A2Q0100043Q00127C010200094Q00792Q0100020002001032012Q000300012Q000C012Q00013Q00013Q00053Q00030C3Q007A6F6E65506C61636542746E03063Q00506172656E7403043Q005465787403013Q004C030C3Q0062746E5F612Q645F7A6F6E65000A3Q00124A012Q00013Q002048014Q000200061E012Q000900013Q0004603Q0009000100124A012Q00013Q00124A2Q0100043Q00127C010200054Q00792Q0100020002001032012Q000300012Q000C012Q00017Q00013Q0003113Q00636C656172426C6F636B65645A6F6E657300033Q00124A012Q00014Q0028012Q000100012Q000C012Q00017Q00023Q00030E3Q0048756257616974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q00030F3Q004175746F53652Q6C456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00043Q0003113Q0053652Q6C436865636B496E74657276616C03043Q006D61746803053Q00666C2Q6F7203123Q007363686564756C6553617665436F6E66696701083Q001216000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q0001000100016Q00017Q000D3Q00030E3Q0073652Q6C496E50726F6772652Q73030A3Q0073652Q6C53746174757303043Q005465787403013Q004C03093Q0073652Q6C5F62757379030A3Q0054657874436F6C6F723303063Q00434F4C4F52532Q033Q00726564030D3Q006D616E75616C53652Q6C42746E030B3Q0062746E5F73652Q6C696E6703073Q0073652Q6C5F747003053Q006D75746564030D3Q0072756E4D616E75616C53652Q6C001F3Q00124A012Q00013Q00061E012Q000D00013Q0004603Q000D000100124A012Q00023Q001275000100043Q00122Q000200056Q00010002000200104Q0003000100124Q00023Q00122Q000100073Q00202Q00010001000800104Q000600016Q00013Q00124A012Q00093Q0012392Q0100043Q00122Q0002000A6Q00010002000200104Q0003000100124Q00023Q00122Q000100043Q00122Q0002000B6Q00010002000200104Q0003000100124Q00023Q00124A2Q0100073Q0020482Q010001000C001032012Q0006000100124A012Q000D3Q0002352Q016Q00E33Q000200012Q000C012Q00013Q00013Q000B3Q00030D3Q006D616E75616C53652Q6C42746E03043Q005465787403013Q004C030C3Q0062746E5F73652Q6C5F6E6F77030A3Q0073652Q6C53746174757303093Q0073652Q6C5F646F6E65030A3Q0073652Q6C5F652Q726F72030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q00726564021E3Q0012AA000200013Q00122Q000300033Q00122Q000400046Q00030002000200102Q00020002000300122Q000200053Q00062Q00030012000100010004603Q0012000100061E012Q000F00013Q0004603Q000F000100124A010300033Q00127C010400064Q007901030002000200064900030012000100010004603Q0012000100124A010300033Q00127C010400074Q007901030002000200103201020002000300124A010200053Q00061E012Q001A00013Q0004603Q001A000100124A010300093Q00204801030003000A0006490003001C000100010004603Q001C000100124A010300093Q00204801030003000B0010320102000800032Q000C012Q00017Q00053Q0003153Q00446973636F72645265706F727473456E61626C656403143Q004641524D5F5245504F52545F494E54455256414C03143Q00446973636F72645265706F72744D696E75746573026Q004E4003113Q0073617665446973636F7264436F6E66696701073Q001233012Q00013Q00122Q000100033Q00202Q00010001000400122Q000100023Q00122Q000100056Q0001000100016Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53746F7003113Q0073617665446973636F7264436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53652Q6C03113Q0073617665446973636F7264436F6E66696701043Q00128F3Q00013Q00124A2Q0100024Q00282Q01000100012Q000C012Q00017Q00063Q0003143Q00446973636F72645265706F72744D696E7574657303043Q006D61746803053Q00666C2Q6F7203143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003113Q0073617665446973636F7264436F6E666967010B3Q00124A2Q0100023Q0020482Q01000100032Q00F000026Q00792Q01000200020012332Q0100013Q00122Q000100013Q00202Q00010001000500122Q000100043Q00122Q000100066Q0001000100016Q00017Q00083Q0003123Q0055736572446973636F7264576562682Q6F6B030C3Q00776562682Q6F6B496E70757403043Q005465787403043Q006773756203043Q005E25732B034Q0003043Q0025732B2403113Q0073617665446973636F7264436F6E666967000E3Q0012E13Q00023Q00206Q000300206Q000400122Q000200053Q00122Q000300068Q0003000200206Q000400122Q000200073Q00122Q000300068Q0003000200128F3Q00013Q00124A012Q00084Q0028012Q000100012Q000C012Q00017Q00013Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757400033Q00124A012Q00014Q0028012Q000100012Q000C012Q00017Q000B3Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E707574030D3Q00646973636F726453746174757303043Q005465787403013Q004C030D3Q00646973636F72645F7361766564030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E7403043Q007461736B03053Q0064656C6179027Q004000113Q0012143Q00018Q0001000100124Q00023Q00122Q000100043Q00122Q000200056Q00010002000200104Q0003000100124Q00023Q00122Q000100073Q00202Q00010001000800104Q0006000100124Q00093Q00206Q000A00122Q0001000B3Q00023501026Q0068012Q000200012Q000C012Q00013Q00013Q00063Q00030D3Q00646973636F726453746174757303063Q00506172656E7403173Q00757064617465446973636F726453746174757354657874030A3Q0054657874436F6C6F723303063Q00434F4C4F525303053Q006D75746564000B3Q00124A012Q00013Q002048014Q000200061E012Q000A00013Q0004603Q000A000100124A012Q00034Q0028012Q0001000100124A012Q00013Q00124A2Q0100053Q0020482Q0100010006001032012Q000400012Q000C012Q00017Q00163Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757403103Q0073656E64446973636F7264456D62656403153Q006765744661726D446973636F7264576562682Q6F6B03113Q00D0A2D0B5D181D182204D41584920485542023Q00806D4C4A4103043Q006E616D6503103Q00D09FD180D0BED0B2D0B5D180D0BAD0B003053Q0076616C756503393Q00D095D181D0BBD0B820D0B2D0B8D0B4D0B8D188D18C20D18DD182D0BE20E2809420776562682Q6F6B20D180D0B0D0B1D0BED182D0B0D0B5D18203063Q00696E6C696E65010003103Q00D098D0BDD182D0B5D180D0B2D0B0D0BB03083Q00746F737472696E6703143Q00446973636F72645265706F72744D696E7574657303073Q0020D0BCD0B8D0BD2Q01030D3Q00646973636F726453746174757303043Q0054657874030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q0072656400243Q00122F3Q00018Q0001000100124Q00023Q00122Q000100036Q00010001000200122Q000200043Q00122Q000300056Q000400026Q00053Q000300302Q00050006000700302Q00050008000900302Q0005000A000B4Q00063Q000300302Q00060006000C00122Q0007000D3Q00122Q0008000E6Q00070002000200122Q0008000F6Q00070007000800102Q00060008000700302Q0006000A00104Q0004000200012Q00A5012Q0004000100124A010200113Q00103201020012000100124A010200113Q00061E012Q002000013Q0004603Q0020000100124A010300143Q00204801030003001500064900030022000100010004603Q0022000100124A010300143Q0020480103000300160010320102001300032Q000C012Q00017Q000A3Q00030A3Q00457370456E61626C656403083Q0045737054722Q657303093Q0045737053746F6E6573030A3Q00457370506C6179657273030C3Q004573705265736F7572636573030A3Q00457370447261676F6E73030A3Q004573705472616365727303083Q004573704E616D6573030B3Q004573705465787453697A6503093Q00457370436F6C6F727300174Q00225Q000A00122Q000100013Q00104Q0001000100122Q000100023Q00104Q0002000100122Q000100033Q00104Q0003000100122Q000100043Q00104Q0004000100122Q000100053Q00104Q0005000100122Q000100063Q00104Q0006000100122Q000100073Q00104Q0007000100122Q000100083Q00104Q0008000100122Q000100093Q00104Q0009000100122Q0001000A3Q00104Q000A00016Q00028Q00017Q000C3Q00030A3Q00457370456E61626C656403083Q0045737054722Q657303093Q0045737053746F6E6573030A3Q00457370506C6179657273030C3Q004573705265736F7572636573030A3Q00457370447261676F6E73030A3Q004573705472616365727303083Q004573704E616D6573030B3Q004573705465787453697A6503093Q00457370436F6C6F7273030A3Q007265667265736845737003123Q007363686564756C6553617665436F6E666967022C3Q0026A03Q0004000100010004603Q0004000100128F000100013Q0004603Q002700010026A03Q0008000100020004603Q0008000100128F000100023Q0004603Q002700010026A03Q000C000100030004603Q000C000100128F000100033Q0004603Q002700010026A03Q0010000100040004603Q0010000100128F000100043Q0004603Q002700010026A03Q0014000100050004603Q0014000100128F000100053Q0004603Q002700010026A03Q0018000100060004603Q0018000100128F000100063Q0004603Q002700010026A03Q001C000100070004603Q001C000100128F000100073Q0004603Q002700010026A03Q0020000100080004603Q0020000100128F000100083Q0004603Q002700010026A03Q0024000100090004603Q0024000100128F000100093Q0004603Q002700010026A03Q00270001000A0004603Q0027000100128F0001000A3Q00124A0102000B4Q002801020001000100124A0102000C4Q00280102000100012Q000C012Q00017Q00093Q0003073Q004B6579436F646503063Q00484F544B455903043Q007469636B03043Q0067656E7603133Q004D6178694875624C617374486F746B65794174028Q0002CD5QCCDC3F030C3Q007365744661726D5374617465030B3Q004661726D456E61626C656401173Q0020482Q013Q000100124A010200023Q0006A42Q010005000100020004603Q000500012Q000C012Q00013Q00124A2Q0100034Q00B500010001000200124A010200043Q0020480102000200050006490002000C000100010004603Q000C000100127C010200064Q004800020001000200263E00020010000100070004603Q001000012Q000C012Q00013Q00124A010200043Q00104B00020005000100122Q000200083Q00122Q000300096Q000300036Q0002000200016Q00017Q00263Q0003093Q007363722Q656E47756903063Q00506172656E74030A3Q006163746976654E6F646503093Q006661726D506861736503043Q007761697403073Q00636F2Q6C656374030F3Q0063616368656444726F70436F756E74030D3Q0066696E6444726F70734E656172028Q00030A3Q0050484153455F54455854030B3Q006175746F46416374697665030D3Q0020C2B720D0B0D0B2D182D0BE46034Q00030F3Q006765744661726D4D6F64655465787403113Q0073652Q73696F6E537461744C6162656C7303053Q00706861736503043Q005465787403053Q0074722Q657303083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q0073746F6E657303123Q0073652Q73696F6E53746F6E65734D696E656403043Q006C2Q6F7403043Q0074696D6503133Q00666F726D617453652Q73696F6E54696D65556903043Q006D6F6465030B3Q007374617475734C6162656C03073Q0056697369626C65030F3Q004175746F53652Q6C456E61626C656403143Q0067657453652Q6C5472692Q676572416D6F756E7403063Q00737472696E6703063Q00666F726D617403083Q00207C2025733A256403233Q002573207C20D0B43A256420D0BA3A2564207C202573207C20D0BBD183D1823A25642573030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403043Q007461736B029A5Q99D93F00823Q00124A012Q00013Q002048014Q000200061E012Q008100013Q0004603Q0081000100124A012Q00033Q00061E012Q001300013Q0004603Q0013000100124A012Q00043Q0026CD3Q000D000100050004603Q000D000100124A012Q00043Q0026A03Q0013000100060004603Q0013000100124A012Q00083Q00126C2Q0100038Q000200029Q0000124Q00073Q00044Q0015000100127C012Q00093Q00128F3Q00073Q00124A012Q000A3Q00124A2Q0100044Q000A5Q00010006493Q001B000100010004603Q001B000100124A012Q00043Q00124A2Q01000B3Q00061E2Q01002100013Q0004603Q0021000100127C2Q01000C3Q00064900010022000100010004603Q0022000100127C2Q01000D3Q00124A0102000E4Q00B500020001000200124A0103000F3Q00204801030003001000061E0103002E00013Q0004603Q002E000100124A0103000F3Q0020530003000300104Q00048Q000500016Q00040004000500102Q00030011000400124A0103000F3Q00204801030003001200061E0103003800013Q0004603Q0038000100124A0103000F3Q00206800030003001200122Q000400133Q00122Q000500146Q00040002000200102Q00030011000400124A0103000F3Q00204801030003001500061E0103004200013Q0004603Q0042000100124A0103000F3Q00206800030003001500122Q000400133Q00122Q000500166Q00040002000200102Q00030011000400124A0103000F3Q00204801030003001700061E0103004C00013Q0004603Q004C000100124A0103000F3Q00206800030003001700122Q000400133Q00122Q000500076Q00040002000200102Q00030011000400124A0103000F3Q00204801030003001800061E0103005500013Q0004603Q0055000100124A0103000F3Q00204801030003001800124A010400194Q00B500040001000200103201030011000400124A0103000F3Q00204801030003001A00061E0103005C00013Q0004603Q005C000100124A0103000F3Q00204801030003001A00103201030011000200124A0103001B3Q00061E0103007C00013Q0004603Q007C000100124A0103001B3Q00204801030003001C00061E0103007C00013Q0004603Q007C000100127C0103000D3Q00124A0104001D3Q00061E0104007000013Q0004603Q0070000100124A0104001E4Q003B01040001000500122Q0006001F3Q00202Q00060006002000122Q000700216Q000800056Q000900046Q0006000900024Q000300063Q00124A0104001B3Q0012850105001F3Q00202Q00050005002000122Q000600226Q000700023Q00122Q000800233Q00122Q000900246Q000A5Q00122Q000B00076Q000C00036Q0005000C000200102Q00040011000500124A010300253Q00204801030003000500127C010400264Q00E30003000200010004605Q00012Q000C012Q00017Q00033Q0003103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C65030C3Q007365744661726D5374617465000C4Q00783Q00013Q00124Q00013Q00124Q00026Q000100016Q000200018Q000200019Q0000124Q00013Q00124Q00036Q000100018Q000200016Q00017Q00093Q00030C3Q00656E73757265506C6179657203043Q007761726E03393Q005B4D415849204855425D20D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD0BED0BBD183D187D0B8D182D18C20506C6179657247756903053Q007072696E74031D3Q005B4D415849204855425D20D0B7D0B0D0BFD183D181D0BA2055493Q2E03053Q007063612Q6C03103Q00622Q6F7473747261704D617869487562030F3Q00687562422Q6F74737472612Q70656403273Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0B7D0B0D0BFD183D181D0BAD0B03A00173Q00124A012Q00014Q00B53Q000100020006493Q0008000100010004603Q0008000100124A012Q00023Q00127C2Q0100034Q00E33Q000200012Q000C012Q00013Q00124A012Q00043Q001229000100058Q0002000100124Q00063Q00122Q000100078Q0002000100064Q0016000100010004603Q001600012Q006B01025Q001205000200083Q00122Q000200023Q00122Q000300096Q000400016Q0002000400012Q000C012Q00017Q00033Q00030F3Q00687562422Q6F74737472612Q706564030B3Q00736F6674436C65616E7570030D3Q006C61756E63684D61786948756200084Q00A8016Q00124Q00013Q00124Q00028Q0001000100124Q00038Q00019Q008Q00017Q00043Q0003053Q007063612Q6C030D3Q006C61756E63684D61786948756203043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q00124A012Q00013Q00124A2Q0100024Q00B33Q000200010006493Q0009000100010004603Q0009000100124A010200033Q00127C010300044Q00F0000400014Q00680102000400012Q000C012Q00017Q00", GetFEnv(), ...);
