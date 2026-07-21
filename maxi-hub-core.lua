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
				if (Enum <= 210) then
					if (Enum <= 104) then
						if (Enum <= 51) then
							if (Enum <= 25) then
								if (Enum <= 12) then
									if (Enum <= 5) then
										if (Enum <= 2) then
											if (Enum <= 0) then
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
											elseif (Enum > 1) then
												Stk[Inst[2]] = Env[Inst[3]];
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
										elseif (Enum <= 3) then
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
										elseif (Enum == 4) then
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
											A = Inst[2];
											Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
										end
									elseif (Enum <= 8) then
										if (Enum <= 6) then
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
										elseif (Enum == 7) then
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
									elseif (Enum <= 10) then
										if (Enum == 9) then
											local B;
											local A;
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
										else
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
										end
									elseif (Enum == 11) then
										Stk[Inst[2]] = {};
									else
										local A;
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
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
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
								elseif (Enum <= 18) then
									if (Enum <= 15) then
										if (Enum <= 13) then
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
										elseif (Enum > 14) then
											local A;
											Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
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
									elseif (Enum <= 16) then
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
									elseif (Enum == 17) then
										Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
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
								elseif (Enum <= 21) then
									if (Enum <= 19) then
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
									elseif (Enum > 20) then
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
										Env[Inst[3]] = Stk[Inst[2]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										do
											return;
										end
									else
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
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Env[Inst[3]] = Stk[Inst[2]];
									end
								elseif (Enum <= 23) then
									if (Enum > 22) then
										local B;
										local T;
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
										A = Inst[2];
										T = Stk[A];
										B = Inst[3];
										for Idx = 1, B do
											T[Idx] = Stk[A + Idx];
										end
									else
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
									end
								elseif (Enum > 24) then
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
								elseif (Stk[Inst[2]] ~= Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 38) then
								if (Enum <= 31) then
									if (Enum <= 28) then
										if (Enum <= 26) then
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
										elseif (Enum == 27) then
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
									elseif (Enum <= 29) then
										local A = Inst[2];
										local T = Stk[A];
										local B = Inst[3];
										for Idx = 1, B do
											T[Idx] = Stk[A + Idx];
										end
									elseif (Enum > 30) then
										local A;
										A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
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
									else
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
									end
								elseif (Enum <= 34) then
									if (Enum <= 32) then
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
									elseif (Enum > 33) then
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
										Stk[Inst[2]] = #Stk[Inst[3]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										if (Stk[Inst[2]] == Inst[4]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum <= 36) then
									if (Enum > 35) then
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
									else
										local A = Inst[2];
										local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Top)));
										Top = (Limit + A) - 1;
										local Edx = 0;
										for Idx = A, Top do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
									end
								elseif (Enum > 37) then
									local B;
									local T;
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
								end
							elseif (Enum <= 44) then
								if (Enum <= 41) then
									if (Enum <= 39) then
										local A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Top));
									elseif (Enum == 40) then
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
								elseif (Enum <= 42) then
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
								elseif (Enum > 43) then
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
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
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
							elseif (Enum <= 47) then
								if (Enum <= 45) then
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum > 46) then
									if (Stk[Inst[2]] <= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
								end
							elseif (Enum <= 49) then
								if (Enum > 48) then
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
								else
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
								end
							elseif (Enum > 50) then
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
							end
						elseif (Enum <= 77) then
							if (Enum <= 64) then
								if (Enum <= 57) then
									if (Enum <= 54) then
										if (Enum <= 52) then
											local B;
											local T;
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
										elseif (Enum == 53) then
											for Idx = Inst[2], Inst[3] do
												Stk[Idx] = nil;
											end
										else
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
										end
									elseif (Enum <= 55) then
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
									elseif (Enum > 56) then
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
									end
								elseif (Enum <= 60) then
									if (Enum <= 58) then
										local A = Inst[2];
										Stk[A](Stk[A + 1]);
									elseif (Enum > 59) then
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
								elseif (Enum <= 62) then
									if (Enum == 61) then
										local B = Stk[Inst[4]];
										if B then
											VIP = VIP + 1;
										else
											Stk[Inst[2]] = B;
											VIP = Inst[3];
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
									end
								elseif (Enum == 63) then
									local Edx;
									local Results;
									local A;
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
								else
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
								end
							elseif (Enum <= 70) then
								if (Enum <= 67) then
									if (Enum <= 65) then
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
											if (Mvm[1] == 366) then
												Indexes[Idx - 1] = {Stk,Mvm[3]};
											else
												Indexes[Idx - 1] = {Upvalues,Mvm[3]};
											end
											Lupvals[#Lupvals + 1] = Indexes;
										end
										Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
									elseif (Enum > 66) then
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
									end
								elseif (Enum <= 68) then
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
								elseif (Enum > 69) then
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
									do
										return;
									end
								else
									local A;
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
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum <= 73) then
								if (Enum <= 71) then
									Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
								elseif (Enum == 72) then
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
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
							elseif (Enum <= 75) then
								if (Enum == 74) then
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
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum > 76) then
								Stk[Inst[2]] = Stk[Inst[3]] % Inst[4];
							else
								Env[Inst[3]] = Stk[Inst[2]];
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
								Env[Inst[3]] = Stk[Inst[2]];
							end
						elseif (Enum <= 90) then
							if (Enum <= 83) then
								if (Enum <= 80) then
									if (Enum <= 78) then
										local A = Inst[2];
										local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
										local Edx = 0;
										for Idx = A, Inst[4] do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
									elseif (Enum > 79) then
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
										if Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									end
								elseif (Enum <= 81) then
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
									A = Inst[2];
									Stk[A] = Stk[A]();
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 82) then
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
							elseif (Enum <= 86) then
								if (Enum <= 84) then
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
								elseif (Enum > 85) then
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
								end
							elseif (Enum <= 88) then
								if (Enum == 87) then
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
							elseif (Enum > 89) then
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
						elseif (Enum <= 97) then
							if (Enum <= 93) then
								if (Enum <= 91) then
									local A;
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
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
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
								elseif (Enum == 92) then
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
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								else
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
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum <= 95) then
								if (Enum > 94) then
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
									do
										return;
									end
								end
							elseif (Enum > 96) then
								local Edx;
								local Results;
								local A;
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
								Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
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
							elseif (Stk[Inst[2]] < Stk[Inst[4]]) then
								VIP = Inst[3];
							else
								VIP = VIP + 1;
							end
						elseif (Enum <= 100) then
							if (Enum <= 98) then
								local A;
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
							elseif (Enum > 99) then
								if (Inst[2] <= Stk[Inst[4]]) then
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
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
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
						elseif (Enum <= 102) then
							if (Enum > 101) then
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
							else
								local A;
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
							end
						elseif (Enum > 103) then
							Env[Inst[3]] = Stk[Inst[2]];
						else
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
						end
					elseif (Enum <= 157) then
						if (Enum <= 130) then
							if (Enum <= 117) then
								if (Enum <= 110) then
									if (Enum <= 107) then
										if (Enum <= 105) then
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
										elseif (Enum == 106) then
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
											Stk[Inst[2]][Inst[3]] = Inst[4];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											do
												return;
											end
										end
									elseif (Enum <= 108) then
										local B;
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
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										B = Stk[Inst[3]];
										Stk[A + 1] = B;
										Stk[A] = B[Inst[4]];
									elseif (Enum == 109) then
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
								elseif (Enum <= 113) then
									if (Enum <= 111) then
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
									elseif (Enum > 112) then
										local A;
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
									end
								elseif (Enum <= 115) then
									if (Enum > 114) then
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
									else
										Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
									end
								elseif (Enum > 116) then
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
								end
							elseif (Enum <= 123) then
								if (Enum <= 120) then
									if (Enum <= 118) then
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
									elseif (Enum > 119) then
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
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
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
									end
								elseif (Enum <= 121) then
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
								elseif (Enum == 122) then
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
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
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
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if (Stk[Inst[2]] < Stk[Inst[4]]) then
										VIP = Inst[3];
									else
										VIP = VIP + 1;
									end
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
							elseif (Enum <= 126) then
								if (Enum <= 124) then
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
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								elseif (Enum == 125) then
									local B;
									local T;
									local A;
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
								end
							elseif (Enum <= 128) then
								if (Enum > 127) then
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
								end
							elseif (Enum == 129) then
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
							end
						elseif (Enum <= 143) then
							if (Enum <= 136) then
								if (Enum <= 133) then
									if (Enum <= 131) then
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
									elseif (Enum == 132) then
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
										local A = Inst[2];
										Stk[A] = Stk[A]();
									end
								elseif (Enum <= 134) then
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
								elseif (Enum == 135) then
									if (Inst[2] < Stk[Inst[4]]) then
										VIP = Inst[3];
									else
										VIP = VIP + 1;
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
								end
							elseif (Enum <= 139) then
								if (Enum <= 137) then
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
								elseif (Enum > 138) then
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
								end
							elseif (Enum <= 141) then
								if (Enum > 140) then
									local A;
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
								else
									local A = Inst[2];
									do
										return Stk[A], Stk[A + 1];
									end
								end
							elseif (Enum == 142) then
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
						elseif (Enum <= 150) then
							if (Enum <= 146) then
								if (Enum <= 144) then
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
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									VIP = Inst[3];
								elseif (Enum > 145) then
									local A;
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
							elseif (Enum <= 148) then
								if (Enum > 147) then
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
							elseif (Enum == 149) then
								Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
							else
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
							end
						elseif (Enum <= 153) then
							if (Enum <= 151) then
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
							elseif (Enum > 152) then
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
							else
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
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 155) then
							if (Enum > 154) then
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
						elseif (Enum > 156) then
							do
								return Stk[Inst[2]];
							end
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
					elseif (Enum <= 183) then
						if (Enum <= 170) then
							if (Enum <= 163) then
								if (Enum <= 160) then
									if (Enum <= 158) then
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
									elseif (Enum > 159) then
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
								elseif (Enum <= 161) then
									VIP = Inst[3];
								elseif (Enum == 162) then
									if (Stk[Inst[2]] > Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = VIP + Inst[3];
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
								end
							elseif (Enum <= 166) then
								if (Enum <= 164) then
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
								elseif (Enum == 165) then
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
								end
							elseif (Enum <= 168) then
								if (Enum > 167) then
									local A;
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
								else
									local A;
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
							elseif (Enum == 169) then
								local Results;
								local Edx;
								local Results, Limit;
								local B;
								local A;
								Stk[Inst[2]] = {};
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
						elseif (Enum <= 176) then
							if (Enum <= 173) then
								if (Enum <= 171) then
									local B;
									local A;
									Stk[Inst[2]] = Env[Inst[3]];
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
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								elseif (Enum == 172) then
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
							elseif (Enum <= 174) then
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							elseif (Enum == 175) then
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
							else
								local Edx;
								local Results;
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
						elseif (Enum <= 179) then
							if (Enum <= 177) then
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
							elseif (Enum == 178) then
								local A = Inst[2];
								local T = Stk[A];
								for Idx = A + 1, Inst[3] do
									Insert(T, Stk[Idx]);
								end
							else
								Stk[Inst[2]] = not Stk[Inst[3]];
							end
						elseif (Enum <= 181) then
							if (Enum == 180) then
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
						elseif (Enum > 182) then
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
						end
					elseif (Enum <= 196) then
						if (Enum <= 189) then
							if (Enum <= 186) then
								if (Enum <= 184) then
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
								elseif (Enum == 185) then
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
									local Edx;
									local Results, Limit;
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
								end
							elseif (Enum <= 187) then
								local A;
								A = Inst[2];
								Stk[A] = Stk[A]();
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
							elseif (Enum == 188) then
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
								Stk[Inst[2]] = Env[Inst[3]];
							else
								local A;
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
						elseif (Enum <= 192) then
							if (Enum <= 190) then
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
							elseif (Enum == 191) then
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
								Stk[Inst[2]]();
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
							end
						elseif (Enum <= 194) then
							if (Enum == 193) then
								local Edx;
								local Results;
								local A;
								A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
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
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						elseif (Enum == 195) then
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
						else
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
						end
					elseif (Enum <= 203) then
						if (Enum <= 199) then
							if (Enum <= 197) then
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
								do
									return;
								end
							elseif (Enum > 198) then
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
								local A = Inst[2];
								do
									return Unpack(Stk, A, A + Inst[3]);
								end
							end
						elseif (Enum <= 201) then
							if (Enum == 200) then
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
						elseif (Enum > 202) then
							do
								return Stk[Inst[2]]();
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
							Stk[Inst[2]] = Inst[3] ~= 0;
						end
					elseif (Enum <= 206) then
						if (Enum <= 204) then
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
						elseif (Enum == 205) then
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
					elseif (Enum <= 208) then
						if (Enum > 207) then
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
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
						end
					elseif (Enum > 209) then
						local A = Inst[2];
						local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
						local Edx = 0;
						for Idx = A, Inst[4] do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
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
						Stk[Inst[2]] = Env[Inst[3]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
				elseif (Enum <= 315) then
					if (Enum <= 262) then
						if (Enum <= 236) then
							if (Enum <= 223) then
								if (Enum <= 216) then
									if (Enum <= 213) then
										if (Enum <= 211) then
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
										elseif (Enum > 212) then
											local A;
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
										else
											local A;
											Stk[Inst[2]] = Env[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Upvalues[Inst[3]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											A = Inst[2];
											Stk[A](Stk[A + 1]);
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
									elseif (Enum <= 214) then
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
									elseif (Enum == 215) then
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
									elseif (Stk[Inst[2]] < Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum <= 219) then
									if (Enum <= 217) then
										do
											return;
										end
									elseif (Enum > 218) then
										local A;
										Stk[Inst[2]]();
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
										Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
									end
								elseif (Enum <= 221) then
									if (Enum > 220) then
										if (Inst[2] < Stk[Inst[4]]) then
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
									end
								elseif (Enum > 222) then
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
								else
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
								end
							elseif (Enum <= 229) then
								if (Enum <= 226) then
									if (Enum <= 224) then
										local Edx;
										local Results;
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
										Results = {Stk[A](Stk[A + 1])};
										Edx = 0;
										for Idx = A, Inst[4] do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
										VIP = VIP + 1;
										Inst = Instr[VIP];
										VIP = Inst[3];
									elseif (Enum == 225) then
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
								elseif (Enum <= 227) then
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
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum > 228) then
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
								else
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
								end
							elseif (Enum <= 232) then
								if (Enum <= 230) then
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
								elseif (Enum == 231) then
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
								end
							elseif (Enum <= 234) then
								if (Enum == 233) then
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
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum > 235) then
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
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 249) then
							if (Enum <= 242) then
								if (Enum <= 239) then
									if (Enum <= 237) then
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
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
									elseif (Enum > 238) then
										local A;
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
									else
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
									end
								elseif (Enum <= 240) then
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
								elseif (Enum == 241) then
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
							elseif (Enum <= 245) then
								if (Enum <= 243) then
									local A;
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
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if not Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum > 244) then
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
								end
							elseif (Enum <= 247) then
								if (Enum == 246) then
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
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
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
								end
							elseif (Enum == 248) then
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
								local B;
								local T;
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
						elseif (Enum <= 255) then
							if (Enum <= 252) then
								if (Enum <= 250) then
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
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								elseif (Enum > 251) then
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
								else
									local A;
									Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
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
							elseif (Enum <= 253) then
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
							elseif (Enum == 254) then
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
						elseif (Enum <= 258) then
							if (Enum <= 256) then
								local A;
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
							elseif (Enum > 257) then
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
							end
						elseif (Enum <= 260) then
							if (Enum > 259) then
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
								Stk[Inst[2]] = #Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] < Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
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
							end
						elseif (Enum > 261) then
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
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 288) then
						if (Enum <= 275) then
							if (Enum <= 268) then
								if (Enum <= 265) then
									if (Enum <= 263) then
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
									elseif (Enum > 264) then
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
										Env[Inst[3]] = Stk[Inst[2]];
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
								elseif (Enum <= 266) then
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
								elseif (Enum == 267) then
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
								end
							elseif (Enum <= 271) then
								if (Enum <= 269) then
									Stk[Inst[2]] = Inst[3] ~= 0;
								elseif (Enum == 270) then
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
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								end
							elseif (Enum <= 273) then
								if (Enum == 272) then
									if (Stk[Inst[2]] ~= Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
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
								end
							elseif (Enum == 274) then
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
							elseif not Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 281) then
							if (Enum <= 278) then
								if (Enum <= 276) then
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
								elseif (Enum > 277) then
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
							elseif (Enum <= 279) then
								if (Stk[Inst[2]] <= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 280) then
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
							else
								local B;
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
								Stk[Inst[2]][Inst[3]] = Inst[4];
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
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							end
						elseif (Enum <= 284) then
							if (Enum <= 282) then
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
							elseif (Enum > 283) then
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]]();
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
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
							else
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
							end
						elseif (Enum <= 286) then
							if (Enum > 285) then
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
							end
						elseif (Enum > 287) then
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
						end
					elseif (Enum <= 301) then
						if (Enum <= 294) then
							if (Enum <= 291) then
								if (Enum <= 289) then
									Stk[Inst[2]][Inst[3]] = Inst[4];
								elseif (Enum == 290) then
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
								else
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
								end
							elseif (Enum <= 292) then
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
								Env[Inst[3]] = Stk[Inst[2]];
							elseif (Enum > 293) then
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
							elseif (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 297) then
							if (Enum <= 295) then
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
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Inst[2] < Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 296) then
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
							end
						elseif (Enum <= 299) then
							if (Enum == 298) then
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
							else
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
							end
						elseif (Enum > 300) then
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
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
						end
					elseif (Enum <= 308) then
						if (Enum <= 304) then
							if (Enum <= 302) then
								local A;
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
							elseif (Enum == 303) then
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
								Stk[Inst[2]] = Stk[Inst[3]];
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
						elseif (Enum <= 306) then
							if (Enum > 305) then
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
							end
						elseif (Enum == 307) then
							local B = Stk[Inst[4]];
							if not B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						else
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
						end
					elseif (Enum <= 311) then
						if (Enum <= 309) then
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
						elseif (Enum > 310) then
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
						end
					elseif (Enum <= 313) then
						if (Enum == 312) then
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
						else
							local A = Inst[2];
							local Results, Limit = _R(Stk[A]());
							Top = (Limit + A) - 1;
							local Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum == 314) then
						if (Stk[Inst[2]] < Inst[4]) then
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
						if not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					end
				elseif (Enum <= 368) then
					if (Enum <= 341) then
						if (Enum <= 328) then
							if (Enum <= 321) then
								if (Enum <= 318) then
									if (Enum <= 316) then
										Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
									elseif (Enum == 317) then
										local A = Inst[2];
										do
											return Unpack(Stk, A, Top);
										end
									else
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
									end
								elseif (Enum <= 319) then
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								elseif (Enum > 320) then
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
							elseif (Enum <= 324) then
								if (Enum <= 322) then
									local A = Inst[2];
									local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
									Top = (Limit + A) - 1;
									local Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								elseif (Enum == 323) then
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
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Env[Inst[3]] = Stk[Inst[2]];
								else
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
								end
							elseif (Enum <= 326) then
								if (Enum == 325) then
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
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								end
							elseif (Enum == 327) then
								Stk[Inst[2]]();
							else
								local A;
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
								Stk[Inst[2]] = Stk[Inst[3]];
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
						elseif (Enum <= 334) then
							if (Enum <= 331) then
								if (Enum <= 329) then
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
								elseif (Enum > 330) then
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
								end
							elseif (Enum <= 332) then
								local A;
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
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
							elseif (Enum == 333) then
								Stk[Inst[2]] = Inst[3];
							else
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
							end
						elseif (Enum <= 337) then
							if (Enum <= 335) then
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
							elseif (Enum == 336) then
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
							else
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
							end
						elseif (Enum <= 339) then
							if (Enum == 338) then
								local A;
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
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
							else
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
							end
						elseif (Enum > 340) then
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
					elseif (Enum <= 354) then
						if (Enum <= 347) then
							if (Enum <= 344) then
								if (Enum <= 342) then
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
								elseif (Enum == 343) then
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
								else
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
								end
							elseif (Enum <= 345) then
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
							elseif (Enum > 346) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
								end
							else
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
						elseif (Enum <= 350) then
							if (Enum <= 348) then
								Stk[Inst[2]] = Stk[Inst[3]] - Inst[4];
							elseif (Enum == 349) then
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
						elseif (Enum <= 352) then
							if (Enum > 351) then
								local B = Inst[3];
								local K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
							elseif (Stk[Inst[2]] == Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 353) then
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
						else
							local K;
							local B;
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
							do
								return;
							end
						end
					elseif (Enum <= 361) then
						if (Enum <= 357) then
							if (Enum <= 355) then
								local A;
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
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								VIP = Inst[3];
							elseif (Enum > 356) then
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
							end
						elseif (Enum <= 359) then
							if (Enum > 358) then
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
							end
						elseif (Enum > 360) then
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
						else
							Stk[Inst[2]] = #Stk[Inst[3]];
						end
					elseif (Enum <= 364) then
						if (Enum <= 362) then
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
						elseif (Enum > 363) then
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
							Stk[A] = Stk[A](Stk[A + 1]);
						else
							local Edx;
							local Results;
							local A;
							Stk[Inst[2]] = Inst[3];
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
					elseif (Enum <= 366) then
						if (Enum > 365) then
							Stk[Inst[2]] = Stk[Inst[3]];
						else
							local A;
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
					elseif (Enum == 367) then
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
						local Edx;
						local Results;
						local A;
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
					end
				elseif (Enum <= 394) then
					if (Enum <= 381) then
						if (Enum <= 374) then
							if (Enum <= 371) then
								if (Enum <= 369) then
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
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 370) then
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
								else
									Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
								end
							elseif (Enum <= 372) then
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
							elseif (Enum > 373) then
								local A;
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
						elseif (Enum <= 377) then
							if (Enum <= 375) then
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
							elseif (Enum == 376) then
								local B;
								local A;
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = {};
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
							end
						elseif (Enum <= 379) then
							if (Enum > 378) then
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
						elseif (Enum == 380) then
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
						else
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
							Stk[Inst[2]]();
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
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum <= 387) then
						if (Enum <= 384) then
							if (Enum <= 382) then
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
							elseif (Enum == 383) then
								local A;
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
							else
								Upvalues[Inst[3]] = Stk[Inst[2]];
							end
						elseif (Enum <= 385) then
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
						elseif (Enum == 386) then
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
							A = Inst[2];
							Stk[A] = Stk[A]();
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
						end
					elseif (Enum <= 390) then
						if (Enum <= 388) then
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
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
						elseif (Enum > 389) then
							local A = Inst[2];
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Stk[Inst[4]]];
						else
							local T;
							local K;
							local B;
							local A;
							Stk[Inst[2]] = {};
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
						end
					elseif (Enum <= 392) then
						if (Enum == 391) then
							local A;
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
					elseif (Enum > 393) then
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
					end
				elseif (Enum <= 407) then
					if (Enum <= 400) then
						if (Enum <= 397) then
							if (Enum <= 395) then
								local A;
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
							elseif (Enum == 396) then
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
								A = Inst[2];
								do
									return Stk[A], Stk[A + 1];
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
							end
						elseif (Enum <= 398) then
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
						elseif (Enum == 399) then
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
						else
							local A;
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
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
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
						end
					elseif (Enum <= 403) then
						if (Enum <= 401) then
							local K;
							local B;
							local A;
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
						elseif (Enum > 402) then
							local A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
						else
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
						end
					elseif (Enum <= 405) then
						if (Enum > 404) then
							local Step;
							local Index;
							local A;
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Env[Inst[3]] = Stk[Inst[2]];
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
							Index = Stk[A];
							Step = Stk[A + 2];
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
						end
					elseif (Enum == 406) then
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
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
					end
				elseif (Enum <= 414) then
					if (Enum <= 410) then
						if (Enum <= 408) then
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
						elseif (Enum > 409) then
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
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						end
					elseif (Enum <= 412) then
						if (Enum == 411) then
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
						end
					elseif (Enum > 413) then
						local A;
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
						Stk[Inst[2]] = Env[Inst[3]];
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
				elseif (Enum <= 417) then
					if (Enum <= 415) then
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
						Env[Inst[3]] = Stk[Inst[2]];
						VIP = VIP + 1;
						Inst = Instr[VIP];
						do
							return;
						end
					elseif (Enum > 416) then
						local A = Inst[2];
						local Results = {Stk[A]()};
						local Limit = Inst[4];
						local Edx = 0;
						for Idx = A, Limit do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					else
						local A;
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
					end
				elseif (Enum <= 419) then
					if (Enum > 418) then
						local A = Inst[2];
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
					else
						Stk[Inst[2]] = Stk[Inst[3]] / Inst[4];
					end
				elseif (Enum > 420) then
					local A = Inst[2];
					local Results = {Stk[A](Stk[A + 1])};
					local Edx = 0;
					for Idx = A, Inst[4] do
						Edx = Edx + 1;
						Stk[Idx] = Results[Edx];
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
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!7D012Q00030C3Q005343524950545F5449544C45030C3Q00F09F94B04D4158492048554203083Q004755495F4E414D4503073Q004D617869487562030D3Q0054454C454752414D5F4C494E4B03153Q00682Q7470733A2Q2F742E6D652F4D4158495F48554203073Q00506C617965727303043Q0067616D65030A3Q0047657453657276696365030A3Q0052756E5365727669636503103Q0055736572496E70757453657276696365030A3Q0047756953657276696365030B3Q00482Q747053657276696365030C3Q0054772Q656E5365727669636503113Q005265706C69636174656453746F72616765030B3Q00434F4E4649475F46494C4503143Q006D6178692D6875622D636F6E6669672E6A736F6E030F3Q0053452Q4C5F53544154455F46494C4503183Q006D6178692D6875622D73652Q6C2D73746174652E6A736F6E030A3Q0055694C616E677561676503023Q00727503093Q004C6F63616C654C6962030E3Q006C6F63616C6542696E64696E677303113Q006372656469747341626F75744C6162656C030F3Q0063726564697473546742752Q746F6E030B3Q004B45595F574542482Q4F4B03793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D6803133Q00444953434F52445F434F4E4649475F46494C4503153Q006D6178692D6875622D646973636F72642E6A736F6E03123Q0055736572446973636F7264576562682Q6F6B034Q0003153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E75746573026Q00244003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F7003063Q00706C6179657203093Q00706C6179657247756903043Q0067656E7603063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47030C3Q00656E73757265506C61796572030B3Q004661726D456E61626C6564030A3Q006661726D54687265616403093Q006661726D52756E4964028Q00030D3Q006661726D54696D65546F74616C030F3Q006661726D54696D655374617274656403123Q0074656C65706F7274436F2Q6E656374696F6E03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503093Q006661726D506861736503043Q0069646C65030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403063Q00484F544B455903043Q00456E756D03073Q004B6579436F64652Q033Q00456E64030F3Q0070656E64696E675072657653746F70030B3Q004D61786948756253746F70030E3Q006661726D436865636B506175736503123Q0073686F756C644661726D436F6E74696E7565030D3Q00697343616E63656C452Q726F7203103Q0063616D657261436F2Q6E656374696F6E030E3Q00612Q706C79496E7669736963616D030E3Q0073746F7043616D6572614C2Q6F70030D3Q00726573746F726543616D657261030F3Q00737461727443616D6572614C2Q6F70030E3Q00434F2Q4C4543545F524144495553026Q004E40030E3Q0054656C65706F7274486569676874027Q004003133Q0053746F6E6554656C65706F7274486569676874026Q000C40030C3Q0069676E6F72656444726F7073030F3Q0063616368656444726F70436F756E7403043Q00564B5F46025Q0080514003073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D417454617267657403113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A65026Q00494003113Q00426C6F636B65645A6F6E6543656E74657203153Q00626C6F636B65645A6F6E6556697375616C5061727403133Q00424C4F434B45445F5A4F4E455F464F4C444552030C3Q004D6178694875625A6F6E6573030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C026Q003440030F3Q0053652Q6C4261746368416D6F756E74025Q004CCD4003143Q0053652Q6C436F636F6E75745468726573686F6C64024Q008093C140030D3Q0053452Q4C5F574F524C445F4944022Q008081CBE4E941030D3Q004641524D5F574F524C445F4944022Q00105C7A23F24103123Q0053452Q4C5F574149545F41465445525F5450026Q001440030A3Q0053452Q4C5F4954454D5303073Q004176616361646F03073Q00436F636F6E757403093Q00436163616F4265616E03053Q00412Q706C6503043Q00436F726E03053Q004C656D6F6E03113Q0073652Q73696F6E53746F6E6544726F707303113Q0073652Q73696F6E54722Q65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E6564030C3Q006661726D5761726E696E6773030D3Q006C6173745761726E696E67417403103Q0073652Q73696F6E54722Q6544726F7073030D3Q004F726269744469616D65746572026Q002C40030A3Q004F7262697453702Q6564029A5Q99F13F030E3Q0044454641554C545F55495F504F5303053Q005544696D322Q033Q006E6577026Q003040026Q00E03F025Q00E070C0030A3Q0073617665645569506F73030C3Q007363722Q656E477569526566030A3Q0068692Q64656E4775697303133Q00736166654D6F6465436F2Q6E656374696F6E73030B3Q0054524144455F48494E545303053Q00747261646503073Q0074726164696E67030A3Q0074726164656F2Q666572030C3Q0074726164657265717565737403083Q0065786368616E676503043Q0073776170030A3Q006F72626974416E676C6503093Q006D6F75736548656C64030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F7573655903103Q0063616E557365436F6E66696746696C6503133Q0073617665436F6E6669675363686564756C6564030C3Q006D61696E4672616D65526566030A3Q0073617665436F6E66696703123Q007363686564756C6553617665436F6E666967030D3Q006C6F616453652Q6C537461746503133Q0068617350656E64696E6753652Q6C5374617465030D3Q007361766553652Q6C5374617465030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F6703123Q0066696E616C697A6553652Q6C526573756D6503103Q006578656375746553652Q6C4974656D73031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F747374726170030A3Q006C6F6164436F6E666967030F3Q00707573684661726D5761726E696E6703103Q00636C6561724661726D5761726E696E6703133Q006765744661726D5761726E696E67735465787403183Q0067657454656C65706F7274486569676874466F724B696E64030F3Q006765744661726D4D6F646554657874030F3Q00535455434B5F465F5345434F4E4453026Q001040030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365030B3Q00736561726368416E676C65030C3Q00736561726368526164697573026Q005440030C3Q00706174726F6C506F696E7473030B3Q00706174726F6C496E646578026Q00F03F030B3Q00687562506F736974696F6E030C3Q004855425F574149545F4D494E026Q000840030C3Q004855425F574149545F4D4158026Q002040030F3Q004855425F4E4541525F524144495553026Q002E40030F3Q006C61737453652Q6C436865636B4174030E3Q0073652Q6C496E50726F6772652Q73030F3Q006D616E75616C53652Q6C546F6B656E03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006765744661726D446973636F7264576562682Q6F6B03113Q0073617665446973636F7264436F6E666967030A3Q0050484153455F5445585403103Q00D0BED0B6D0B8D0B4D0B0D0BDD0B8D0B503063Q00736561726368030A3Q00D0BFD0BED0B8D181D0BA03043Q006D696E65030C3Q00D0B4D0BED0B1D18BD187D0B003043Q007761697403133Q00D0B6D0B4D191D0BC20D0B4D180D0BED0BFD18B03073Q00636F2Q6C65637403083Q00D181D0B1D0BED18003043Q0073652Q6C030E3Q00D0BFD180D0BED0B4D0B0D0B6D0B02Q033Q00687562030A3Q00D186D0B5D0BDD182D180030D3Q006C6F61644C6F63616C654C696203013Q004C030E3Q0072656769737465724C6F63616C65030A3Q006765745461624465667303103Q007265667265736850686173655465787403173Q00757064617465446973636F72645374617475735465787403163Q007570646174654372656469747341626F75745465787403123Q00612Q706C794D6178694875624C6F63616C65030D3Q0073657455694C616E677561676503143Q0067657454656C65706F7274537061776E5061727403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C030B3Q0072656C65617365464B657903103Q0072656C656173654D6F757365486F6C6403133Q0073746F704368617261637465724D6F74696F6E03163Q00676574426C6F636B65645A6F6E6548616C6653697A6503143Q00676574426C6F636B65645A6F6E654D696E4D617803123Q006973506F73496E426C6F636B65645A6F6E6503133Q0069734E6F6465496E426C6F636B65645A6F6E6503173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00757064617465426C6F636B65645A6F6E6556697375616C03163Q00736574426C6F636B65645A6F6E654174506C61796572030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C655761697403183Q00696E74652Q7275707469626C6557616974466F7253652Q6C03123Q0063617074757265487562506F736974696F6E030E3Q00676574487562506F736974696F6E03093Q0069734E656172487562030D3Q0074656C65706F7274546F487562030B3Q00687562526573745761697403143Q0072657475726E546F48756241667465724E6F6465030C3Q0073686F756C645072652Q734603063Q007072652Q7346030B3Q00686F6C644D6F757365417403073Q00636C69636B4174030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73030F3Q0067657450617274506F736974696F6E030F3Q0067657441696D5363722Q656E506F73030B3Q0069734E6F6465416C697665030D3Q006765744E6F64654865616C7468030A3Q0072657365744175746F46030B3Q007570646174654175746F46030B3Q00676574486974626F786573030E3Q00676574436F2Q6C65637450617274030D3Q006765744E6F646543656E746572030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473030E3Q007069636B4265737454617267657403133Q0072656275696C64506174726F6C506F696E7473030E3Q0074656C65706F727453656172636803103Q0044524F505F4D4F44454C5F48494E545303093Q00462Q6F644D6F64656C03123Q00572Q6F645265736F75726365734D6F64656C03143Q00436F2Q7065725265736F75726365734D6F64656C03123Q004C6561665265736F75726365734D6F64656C030E3Q005265736F75726365734D6F64656C03133Q0069735265736F7572636544726F704D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C030D3Q00697344726F7049676E6F72656403113Q006D61726B44726F70436F2Q6C656374656403123Q00697356616C6964436F2Q6C65637444726F7003173Q0066696E6443616D6572615265736F7572636544726F7073030D3Q0066696E6444726F70734E656172030B3Q00636F2Q6C65637450617274030F3Q00636F2Q6C656374412Q6C44726F7073030A3Q00612Q7461636B50617274030F3Q0064726F707341726553652Q746C656403103Q0077616974416E645363616E44726F707303103Q006765744D696E65416E63686F72506F7303103Q0074656C65706F7274546F54617267657403083Q0069734F7572477569030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A656374030A3Q007363616E547261646573030D3Q00686964654F7468657247756973030A3Q00636C6561725461626C65030C3Q0073746F70536166654D6F6465030D3Q007374617274536166654D6F646503123Q006765745265736F7572636573466F6C64657203113Q006765745265736F75726365416D6F756E7403143Q0067657453652Q6C5472692Q676572416D6F756E74030D3Q006E2Q6564734175746F53652Q6C030E3Q006765744661726D5365636F6E6473030B3Q00682Q74705265717565737403123Q00706F7374446973636F7264576562682Q6F6B03103Q0073656E64446973636F7264456D62656403173Q006765745265736F75726365734F7665724F6E655465787403153Q0067657453652Q73696F6E53746174734669656C647303153Q006C6F674661726D53652Q73696F6E446973636F726403133Q0077616974466F7243686172616374657248727003083Q0073652Q6C57616974030D3Q0067657453652Q6C52656D6F746503163Q00676574576F726C6454656C65706F727452656D6F7465030D3Q00776F726C6454656C65706F727403103Q0073652Q6C5265736F757263654974656D030C3Q0072756E53652Q6C4379636C65030B3Q0072756E4175746F53652Q6C030D3Q0072756E4D616E75616C53652Q6C03103Q006D6179626552756E4175746F53652Q6C03123Q006D6179626552756E4661726D5265706F7274030E3Q0072756E5365617263685068617365030D3Q006B692Q6C4661726D4C2Q6F707303083Q0073746F704661726D030B3Q00736F6674436C65616E7570030A3Q0066752Q6C556E6C6F616403093Q0073746172744661726D030F3Q004D617869487562476574537461747303183Q004D6178694875625061757365466F72496E76656E746F7279031B3Q004D617869487562526573756D654166746572496E76656E746F727903113Q005F4D61786948756255494C69627261727903123Q004D6178694875624F2Q66696369616C52617703113Q004D61786948756252656D6F746542617365030F3Q004D6178694875625265706F4F6E6C7903073Q00482Q747047657403043Q007479706503063Q00737472696E6703053Q00652Q726F72033F3Q005B4D415849204855425D20554920D182D0BED0BBD18CD0BAD0BE20D18120D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD0BED0B3D0BE20D180D0B5D0BFD0BE03083Q007265616466696C6503063Q00697366696C6503063Q0069706169727303183Q006D6178692D6875622F6D6178692D6875622D75692E6C7561030F3Q006D6178692D6875622D75692E6C756103583Q005B4D415849204855425D20D09DD183D0B6D0B5D0BD206D6178692D6875622D75692E6C75612028D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD18BD0B920D180D0B5D0BFD0BE20D0B8D0BBD0B820776F726B737061636529030A3Q006C6F6164737472696E6703103Q00406D6178692D6875622D75692E6C756103173Q005B4D415849204855425D20554920636F6D70696C653A2003083Q00746F737472696E6703133Q005B4D415849204855425D2055492072756E3A20030C3Q004D61786948756255494C696203093Q0055495F4C41594F555403073Q0050414E454C5F57026Q00694003073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58026Q006B4003063Q00524F57335F59026Q006C4003063Q0046552Q4C5F57025Q00407A40030E3Q00534C494445525F50414E454C5F48026Q006440030E3Q0053452Q53494F4E5F424F44595F59025Q00804140030D3Q00534C494445525F424F44595F59026Q004440030A3Q004D494E455F424F585F48025Q00C06540030D3Q00534C49444552535F424F585F48026Q005C40030A3Q00534146455F424F585F48026Q005640030D3Q00544F2Q474C455F595F53544550026Q004640030D3Q00534C494445525F595F5354455003163Q006275696C644D61786948756243726564697473546162030F3Q00687562422Q6F74737472612Q70656403103Q00622Q6F7473747261704D617869487562030D3Q006C61756E63684D617869487562030F3Q004D61786948756252656C61756E636803083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C6179657247756903053Q007072696E7403283Q005B4D415849204855425D20D0BCD0BED0B4D183D0BBD18C20D0B7D0B0D0B3D180D183D0B6D0B5D0BD03043Q007461736B03053Q0064656665720036032Q001235012Q00023Q00124Q00013Q00124Q00043Q00124Q00033Q00124Q00063Q00124Q00053Q00124Q00083Q00206Q000900122Q000200078Q0002000200124Q00073Q00124Q00083Q00206Q000900122Q0002000A8Q0002000200124Q000A3Q00124Q00083Q00206Q000900122Q0002000B8Q0002000200124Q000B3Q00124Q00083Q00206Q000900122Q0002000C8Q0002000200124Q000C3Q00124Q00083Q00206Q000900122Q0002000D8Q0002000200124Q000D3Q00124Q00083Q00206Q000900122Q0002000E8Q0002000200124Q000E3Q00124Q00083Q00206Q000900122Q0002000F8Q0002000200124Q000F3Q00124Q00113Q00124Q00103Q00124Q00133Q00124Q00123Q00124Q00153Q00124Q00149Q003Q00124Q00169Q003Q00124Q00179Q003Q00124Q00189Q003Q00124Q00193Q00124Q001B3Q00124Q001A3Q00124Q001D3Q00124Q001C3Q00124Q001F3Q00124Q001E8Q00013Q00124Q00203Q00124Q00223Q00124Q00218Q00013Q00124Q00238Q00013Q00124Q00249Q003Q00124Q00259Q003Q00124Q00269Q003Q00124Q00273Q00124Q00283Q00122Q000100298Q0002000200264Q00540001002A0004A13Q005400010012023Q00294Q00853Q000100020012683Q00273Q0004A13Q005600010012023Q002B3Q0012683Q00273Q0002477Q001250012Q002C9Q003Q00124Q002D9Q003Q00124Q002E3Q00124D012Q00303Q0012683Q002F3Q00124D012Q00303Q0012683Q00313Q00124D012Q00303Q0012683Q00324Q004A016Q00124Q00339Q003Q00124Q00349Q003Q00124Q00353Q00124Q00373Q00124Q00363Q00124Q00393Q00124Q00383Q00124D012Q00303Q001265012Q003A3Q00124Q00303Q00124Q003B3Q00124Q003D3Q00206Q003E00206Q003F00124Q003C9Q003Q00124Q00403Q00124Q00283Q001202000100273Q00203F2Q01000100412Q0093012Q00020002002625012Q007F0001002A0004A13Q007F00010012023Q00273Q00203F014Q00410012683Q00404Q000D016Q0012683Q00423Q0002473Q00013Q0012683Q00433Q0002473Q00023Q0012683Q00444Q00357Q0012683Q00453Q0002473Q00033Q0012683Q00463Q0002473Q00043Q0012683Q00473Q0002473Q00053Q0012683Q00483Q0002473Q00063Q0012263Q00493Q00124Q004B3Q00124Q004A3Q00124Q004D3Q00124Q004C3Q00124Q004F3Q00124Q004E9Q003Q00124Q00503Q00124Q00303Q00124Q00513Q00124Q00533Q00124Q00528Q00013Q00124Q00548Q00013Q00124Q00559Q003Q00124Q00568Q00013Q00124Q00578Q00013Q00124Q00588Q00013Q00124Q00598Q00013Q00124Q005A9Q003Q00124Q005B9Q003Q00124Q005C9Q003Q00124Q005D3Q00124Q005F3Q00124Q005E9Q003Q00124Q00609Q003Q00124Q00613Q00124Q00633Q00124Q00628Q00013Q00124Q00643Q00124Q00663Q00124Q00653Q00124Q00683Q00124Q00673Q00124Q006A3Q00124Q00693Q00124Q006C3Q00124Q006B3Q00124Q006E3Q00124Q006D3Q00124Q00703Q00124Q006F8Q00063Q00122Q000100723Q00122Q000200733Q00122Q000300743Q00122Q000400753Q00122Q000500763Q00122Q000600778Q000600010012683Q00713Q001228012Q00303Q00124Q00783Q00124Q00303Q00124Q00793Q00124Q00303Q00124Q007A9Q003Q00124Q007B9Q003Q00124Q007C3Q00124D012Q00303Q00127B012Q007D3Q00124Q007F3Q00124Q007E3Q00124Q00813Q00124Q00803Q00124Q00833Q00206Q008400122Q000100303Q00122Q000200853Q00122Q000300863Q00124D010400874Q001F3Q0004000200124Q00829Q003Q00124Q00889Q003Q00124Q00899Q003Q00124Q008A9Q003Q00124Q008B4Q000B3Q00063Q0012340001008D3Q00122Q0002008E3Q00122Q0003008F3Q00122Q000400903Q00122Q000500913Q00122Q000600928Q000600010012683Q008C3Q00125D3Q00303Q00124Q00939Q003Q00124Q00943Q00124Q00303Q00122Q000100303Q00122Q000100963Q00124Q00953Q0002473Q00073Q001250012Q00979Q003Q00124Q00989Q003Q00124Q00993Q0002473Q00083Q0012683Q009A3Q0002473Q00093Q0012683Q009B3Q0002473Q000A3Q0012683Q009C3Q0002473Q000B3Q0012683Q009D3Q0002473Q000C3Q0012683Q009E3Q0002473Q000D3Q0012683Q009F3Q0002473Q000E3Q0012683Q00A03Q0002473Q000F3Q0012683Q00A13Q0002473Q00103Q0012683Q00A23Q0002473Q00113Q0012683Q00A33Q0002473Q00123Q0012683Q00A43Q0002473Q00133Q0012683Q00A53Q0002473Q00143Q0012683Q00A63Q0002473Q00153Q0012683Q00A73Q0002473Q00163Q0012683Q00A83Q0002473Q00173Q001237012Q00A93Q00124Q00AB3Q00124Q00AA9Q003Q00124Q00AC9Q003Q00124Q00AD3Q00124Q00303Q00124Q00AE3Q00124Q00303Q0012683Q00AF3Q0012593Q00B13Q00124Q00B09Q003Q00124Q00B23Q00124Q00B43Q00124Q00B39Q003Q00124Q00B53Q00124Q00B73Q00124Q00B63Q00124D012Q00B93Q00120E012Q00B83Q00124Q00BB3Q00124Q00BA3Q00124Q00303Q00124Q00BC9Q003Q00124Q00BD3Q00124Q00303Q00124Q00BE3Q00124Q00303Q0012683Q00BF3Q0012023Q00213Q0020115Q004B0012683Q00C03Q0002473Q00183Q0012683Q00C13Q0002473Q00193Q00124C3Q00C29Q00000700304Q003900C400304Q00C500C600304Q00C700C800304Q00C900CA00304Q00CB00CC00304Q00CD00CE00304Q00CF00D000124Q00C33Q0002473Q001A3Q0012683Q00D13Q0002473Q001B3Q0012683Q00D23Q0002473Q001C3Q0012683Q00D33Q0002473Q001D3Q0012683Q00D43Q0002473Q001E3Q0012683Q00D53Q0002473Q001F3Q0012683Q00D63Q0002473Q00203Q0012683Q00D73Q0002473Q00213Q0012683Q00D83Q0002473Q00223Q0012683Q00D93Q0002473Q00233Q0012683Q00DA4Q00357Q0012683Q00DB3Q0012023Q00DC3Q000247000100244Q003A3Q000200010002473Q00253Q0012683Q00DD3Q0002473Q00263Q0012683Q00DE3Q0002473Q00273Q0012683Q00DF3Q0002473Q00283Q0012683Q00E03Q0002473Q00293Q0012683Q00E13Q0002473Q002A3Q0012683Q00E23Q0002473Q002B3Q0012683Q00E33Q0002473Q002C3Q0012683Q00E43Q0002473Q002D3Q0012683Q00E53Q0002473Q002E3Q0012683Q00E63Q0002473Q002F3Q0012683Q00E73Q0002473Q00303Q0012683Q00E83Q0002473Q00313Q0012683Q00E93Q0002473Q00323Q0012683Q00EA3Q0002473Q00333Q0012683Q00EB3Q0002473Q00343Q0012683Q00EC3Q0002473Q00353Q0012683Q00ED3Q0002473Q00363Q0012683Q00EE3Q0002473Q00373Q0012683Q00EF3Q0002473Q00383Q0012683Q00F03Q0002473Q00393Q0012683Q00F13Q0002473Q003A3Q0012683Q00F23Q0002473Q003B3Q0012683Q00F33Q0002473Q003C3Q0012683Q00F43Q0002473Q003D3Q0012683Q00F53Q0002473Q003E3Q0012683Q00F63Q0002473Q003F3Q0012683Q00F73Q0002473Q00403Q0012683Q00F83Q0002473Q00413Q0012683Q00F93Q0002473Q00423Q0012683Q00FA3Q0002473Q00433Q0012683Q00FB3Q0002473Q00443Q0012683Q00FC3Q0002473Q00453Q0012683Q00FD3Q0002473Q00463Q0012683Q00FE3Q0002473Q00473Q0012683Q00FF3Q0002473Q00483Q0012684Q00012Q0002473Q00493Q0012683Q002Q012Q0002473Q004A3Q0012683Q0002012Q0002473Q004B3Q0012683Q0003012Q0002473Q004C3Q0012B73Q0004017Q00053Q00122Q00010006012Q00122Q00020007012Q00122Q00030008012Q00122Q00040009012Q00122Q0005000A017Q000500010012683Q0005012Q0002473Q004D3Q0012683Q000B012Q0002473Q004E3Q0012683Q000C012Q0002473Q004F3Q0012683Q000D012Q0002473Q00503Q0012683Q000E012Q0002473Q00513Q0012683Q000F012Q0002473Q00523Q0012683Q0010012Q0002473Q00533Q0012683Q0011012Q0002473Q00543Q0012683Q0012012Q0002473Q00553Q0012683Q0013012Q0002473Q00563Q0012683Q0014012Q0002473Q00573Q0012683Q0015012Q0002473Q00583Q0012683Q0016012Q0002473Q00593Q0012683Q0017012Q0002473Q005A3Q0012683Q0018012Q0002473Q005B3Q0012683Q0019012Q0002473Q005C3Q0012683Q001A012Q0002473Q005D3Q0012683Q001B012Q0002473Q005E3Q0012683Q001C012Q0002473Q005F3Q0012683Q001D012Q0002473Q00603Q0012683Q001E012Q0002473Q00613Q0012683Q001F012Q0002473Q00623Q0012683Q0020012Q0002473Q00633Q0012683Q0021012Q0002473Q00643Q0012683Q0022012Q0002473Q00653Q0012683Q0023012Q0002473Q00663Q0012683Q0024012Q0002473Q00673Q0012683Q0025012Q0002473Q00683Q0012683Q0026012Q0002473Q00693Q0012683Q0027012Q0002473Q006A3Q0012683Q0028012Q0002473Q006B3Q0012683Q0029012Q0002473Q006C3Q0012683Q002A012Q0002473Q006D3Q0012683Q002B012Q0002473Q006E3Q0012683Q002C012Q0002473Q006F3Q0012683Q002D012Q0002473Q00703Q0012683Q002E012Q0002473Q00713Q0012683Q002F012Q0002473Q00723Q0012683Q0030012Q0002473Q00733Q0012683Q0031012Q0002473Q00743Q0012683Q0032012Q0002473Q00753Q0012683Q0033012Q0002473Q00763Q0012683Q0034012Q0002473Q00773Q0012683Q0035012Q0002473Q00783Q0012683Q0036012Q0002473Q00793Q0012683Q0037012Q0002473Q007A3Q0012683Q0038012Q0002473Q007B3Q0012683Q0039012Q0002473Q007C3Q0012683Q003A012Q0002473Q007D3Q00128B3Q003B012Q00124Q00273Q00122Q0001003A012Q00104Q0041000100124Q00403Q00064Q003502013Q0004A13Q003502010012023Q00403Q0012020001003A012Q0006183Q0035020100010004A13Q003502010012023Q00DC3Q001202000100404Q003A3Q000200012Q00357Q0012683Q00403Q0002473Q007E3Q0012683Q003C012Q0012023Q00273Q00124D2Q01003D012Q0002470002007F4Q00723Q000100020012023Q00273Q00124D2Q01003E012Q000247000200804Q00723Q000100020012023Q00273Q00124D2Q01003F012Q000247000200814Q00FB3Q0001000200124Q00283Q00122Q000100298Q0002000200264Q004E0201002A0004A13Q004E02010012023Q00294Q00853Q00010002000613012Q004F020100010004A13Q004F02010012023Q002B3Q00124D2Q010040013Q00C300013Q00010006132Q0100C7020100010004A13Q00C702012Q0035000100013Q00124D01020041013Q00C300023Q00020006130102005A020100010004A13Q005A020100124D01020042013Q00C300023Q000200124D01030043013Q00C300033Q00032Q000D010400013Q00061800030060020100040004A13Q006002012Q004000036Q000D010300013Q00062D0002008502013Q0004A13Q00850201001202000400283Q0012DE000500083Q00122Q00060044015Q0005000500064Q00040002000200262Q000400850201002A0004A13Q00850201000247000400823Q001202000500DC3Q00064100060083000100012Q006E012Q00024Q00A501050002000600062D0005008502013Q0004A13Q0085020100120200070045013Q006E010800064Q009301070002000200124D01080046012Q00065F01070085020100080004A13Q00850201002610010600850201001F0004A13Q008502012Q006E010700044Q006E010800064Q009301070002000200061301070080020100010004A13Q008002012Q006E2Q0100063Q0004A13Q0085020100062D0003008502013Q0004A13Q0085020100120200070047012Q00124D01080048013Q003A0007000200010006132Q0100A6020100010004A13Q00A60201000613010300A6020100010004A13Q00A60201001202000400283Q00120200050049013Q0093010400020002002625010400A60201002A0004A13Q00A60201001202000400283Q0012020005004A013Q0093010400020002002625010400A60201002A0004A13Q00A602010012020004004B013Q000B000500023Q00124D0106004C012Q00124D0107004D013Q001D0005000200012Q00A50104000200060004A13Q00A402010012020009004A013Q006E010A00084Q009301090002000200062D000900A402013Q0004A13Q00A4020100120200090049013Q006E010A00084Q00930109000200022Q006E2Q0100093Q0004A13Q00A602010006550004009A020100020004A13Q009A02010006132Q0100AB020100010004A13Q00AB020100120200040047012Q00124D0105004E013Q003A0004000200010012020004004F013Q006E010500013Q00124D01060050013Q004E000400060005000613010400B8020100010004A13Q00B8020100120200060047012Q00129F00070051012Q00122Q00080052015Q000900056Q0008000200024Q0007000700084Q000600020001001202000600DC4Q006E010700044Q00A5010600020007000613010600C4020100010004A13Q00C4020100120200080047012Q00129F00090053012Q00122Q000A0052015Q000B00076Q000A000200024Q00090009000A4Q00080002000100124D01080040013Q00723Q000800072Q00D600015Q0012023Q00283Q001202000100294Q0093012Q00020002002625012Q00D00201002A0004A13Q00D002010012023Q00294Q00853Q00010002000613012Q00D1020100010004A13Q00D102010012023Q002B3Q00124D2Q010040013Q0053014Q000100124Q0054019Q000D00122Q00010056012Q00122Q00020057017Q0001000200122Q00010058012Q00122Q00020057017Q0001000200122Q00010059012Q0012360002005A017Q0001000200122Q0001005B012Q00122Q0002005C017Q0001000200122Q0001005D012Q00122Q0002005E017Q0001000200122Q0001005F012Q00122Q00020060013Q00733Q0001000200122Q00010061012Q00122Q00020062017Q0001000200122Q00010063012Q00122Q00020064017Q0001000200122Q00010065012Q00122Q00020066017Q0001000200124D2Q010067012Q00123600020068017Q0001000200122Q00010069012Q00122Q0002006A017Q0001000200122Q0001006B012Q00122Q0002006C017Q0001000200122Q0001006D012Q00122Q0002004B4Q00723Q000100020012683Q0055012Q0002473Q00843Q0012683Q006E013Q000D016Q0012683Q006F012Q0002473Q00853Q0012683Q0070012Q0002473Q00863Q0012683Q0071012Q0012023Q00273Q00124D2Q010072012Q000247000200874Q00723Q000100020012023Q00253Q00062D3Q000F03013Q0004A13Q000F03010012023Q00263Q000613012Q002D030100010004A13Q002D03010012023Q00083Q00124D01020073013Q0086014Q00022Q0093012Q00020002000613012Q001B030100010004A13Q001B03010012023Q00083Q0012F100010074019Q000100122Q00020075019Q00026Q000200010012023Q00073Q00124D2Q010076013Q00C35Q0001000613012Q0026030100010004A13Q002603010012023Q00073Q00126C2Q010077019Q000100122Q00020075019Q00026Q000200020012683Q00253Q0012AB3Q00253Q00122Q00020078019Q000200122Q00020079017Q0002000200124Q00263Q0012023Q007A012Q0012F60001007B017Q0002000100124Q007C012Q00122Q0001007D019Q0001000247000100884Q003A3Q000200012Q00D93Q00013Q00893Q00143Q0003063Q00706C6179657203093Q00706C6179657247756903063Q00506172656E7403043Q0067616D6503083Q0049734C6F6164656403063Q004C6F6164656403043Q005761697403073Q00506C6179657273030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030E3Q0046696E6446697273744368696C6403093Q00506C61796572477569030C3Q0057616974466F724368696C64026Q003E40030E3Q004D6178694875624B65794761746503073Q0044657374726F7903043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C0003053Q007063612Q6C00443Q0012023Q00013Q00062D3Q000C00013Q0004A13Q000C00010012023Q00023Q00062D3Q000C00013Q0004A13Q000C00010012023Q00023Q00203F014Q000300062D3Q000C00013Q0004A13Q000C00012Q000D012Q00014Q009D3Q00023Q0012023Q00043Q00202C014Q00052Q0093012Q00020002000613012Q0015000100010004A13Q001500010012023Q00043Q00203F014Q000600202C014Q00072Q003A3Q000200010012023Q00083Q00203F014Q0009000613012Q001E000100010004A13Q001E0001001202000100083Q00203F2Q010001000A00202C2Q01000100072Q00932Q01000200022Q006E012Q00013Q0012683Q00013Q00123B2Q0100013Q00202Q00010001000B00122Q0003000C6Q00010003000200122Q000100023Q00122Q000100023Q00062Q0001002D000100010004A13Q002D0001001202000100013Q0020242Q010001000D00122Q0003000C3Q00122Q0004000E6Q00010004000200122Q000100023Q001202000100023Q0006132Q010032000100010004A13Q003200012Q000D2Q016Q009D000100023Q001202000100023Q00202C2Q010001000B00124D0103000F4Q00A32Q010003000200062D0001003A00013Q0004A13Q003A000100202C0102000100102Q003A000200020001001202000200113Q00203F01020002001200262501020041000100130004A13Q00410001001202000200143Q00024700036Q003A0002000200012Q000D010200014Q009D000200024Q00D93Q00013Q00013Q00043Q0003043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646500053Q0012223Q00013Q00122Q000100033Q00202Q00010001000400104Q000200016Q00017Q00033Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964030E3Q006661726D436865636B5061757365010D3Q001202000100013Q00062D0001000B00013Q0004A13Q000B0001001202000100023Q00065F012Q0009000100010004A13Q00090001001202000100034Q00B3000100013Q0004A13Q000B00012Q004000016Q000D2Q0100014Q009D000100024Q00D93Q00017Q00083Q0003063Q00747970656F6603063Q00737472696E6703053Q006C6F77657203043Q0066696E6403063Q0063616E63656C026Q00F03F0003073Q0063616E63652Q6C01213Q001202000100014Q006E01026Q00932Q01000200020026102Q010007000100020004A13Q000700012Q000D2Q016Q009D000100023Q001202000100023Q0020402Q01000100034Q00028Q00010002000200122Q000200023Q00202Q0002000200044Q000300013Q00122Q000400053Q00122Q000500066Q000600016Q00020006000200262Q0002001E000100070004A13Q001E0001001202000200023Q00200E0002000200044Q000300013Q00122Q000400083Q00122Q000500066Q000600016Q00020006000200262Q0002001E000100070004A13Q001E00012Q004000026Q000D010200014Q009D000200024Q00D93Q00017Q00013Q0003053Q007063612Q6C00043Q0012023Q00013Q00024700016Q003A3Q000200012Q00D93Q00013Q00013Q00043Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q00456E756D03093Q00496E7669736963616D00063Q00129C3Q00013Q00122Q000100033Q00202Q00010001000200202Q00010001000400104Q000200016Q00017Q00023Q0003103Q0063616D657261436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400093Q0012023Q00013Q00062D3Q000800013Q0004A13Q000800010012023Q00013Q00202C014Q00022Q003A3Q000200012Q00357Q0012683Q00014Q00D93Q00017Q00023Q00030E3Q0073746F7043616D6572614C2Q6F7003053Q007063612Q6C00063Q0012023Q00014Q0047012Q000100010012023Q00023Q00024700016Q003A3Q000200012Q00D93Q00013Q00013Q00063Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03043Q00456E756D03043Q005A2Q6F6D000A3Q0012023Q00013Q001202000100033Q00203F2Q01000100040006132Q010008000100010004A13Q00080001001202000100053Q00203F2Q010001000200203F2Q0100010006001099012Q000200012Q00D93Q00017Q00063Q00030E3Q0073746F7043616D6572614C2Q6F70030E3Q00612Q706C79496E7669736963616D03103Q0063616D657261436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374000B3Q00127D012Q00018Q0001000100124Q00028Q0001000100124Q00043Q00206Q000500206Q000600122Q000200028Q0002000200124Q00038Q00017Q00053Q0003063Q00747970656F6603093Q00777269746566696C6503083Q0066756E6374696F6E03083Q007265616466696C6503063Q00697366696C6500133Q0012023Q00013Q001202000100024Q0093012Q00020002002625012Q000F000100030004A13Q000F00010012023Q00013Q001202000100044Q0093012Q00020002002625012Q000F000100030004A13Q000F00010012023Q00013Q001202000100054Q0093012Q00020002002610012Q0010000100030004A13Q001000012Q00408Q000D012Q00014Q009D3Q00024Q00D93Q00017Q00253Q0003103Q0063616E557365436F6E66696746696C65030E3Q0054656C65706F727448656967687403133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A6503113Q00426C6F636B65645A6F6E6543656E74657203013Q005803013Q005903013Q005A030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F70030A3Q0055694C616E6775616765030C3Q006D61696E4672616D6552656603083Q00506F736974696F6E03083Q005569585363616C6503053Q005363616C6503093Q005569584F2Q6673657403063Q004F2Q6673657403083Q005569595363616C6503093Q005569594F2Q6673657403053Q007063612Q6C005F3Q0012023Q00014Q00853Q00010002000613012Q0005000100010004A13Q000500012Q00D93Q00014Q000B5Q00140012712Q0100023Q00104Q0002000100122Q000100033Q00104Q0003000100122Q000100043Q00104Q0004000100122Q000100053Q00104Q0005000100122Q000100063Q00104Q0006000100122Q000100073Q00104Q0007000100122Q000100083Q00104Q0008000100122Q000100093Q00104Q0009000100122Q0001000A3Q00104Q000A000100122Q0001000B3Q00104Q000B000100122Q0001000C3Q00104Q000C000100122Q0001000D3Q00104Q000D000100122Q0001000E3Q00104Q000E000100122Q0001000F3Q00104Q000F000100122Q000100103Q00104Q0010000100122Q000100113Q00062Q0001003100013Q0004A13Q003100012Q000B000100033Q0012F9000200113Q00202Q00020002001200122Q000300113Q00202Q00030003001300122Q000400113Q00202Q0004000400144Q0001000300010006132Q010032000100010004A13Q003200012Q0035000100013Q001099012Q00110001001204000100153Q00104Q0015000100122Q000100163Q00104Q0016000100122Q000100173Q00104Q0017000100122Q000100183Q00104Q0018000100122Q000100193Q00104Q001900010012020001001A3Q001005012Q001A000100122Q0001001B3Q00104Q001B000100122Q0001001C3Q00104Q001C000100122Q0001001D3Q00062Q0001005400013Q0004A13Q005400010012020001001D3Q00209400010001001E00202Q00020001001200202Q00020002002000104Q001F000200202Q00020001001200202Q00020002002200104Q0021000200202Q00020001001300202Q00020002002000104Q0023000200202Q00020001001300202Q00020002002200104Q00240002001202000100253Q00064100023Q000100012Q006E017Q00A52Q010002000200062D0001005E00013Q0004A13Q005E0001001202000300253Q00064100040001000100012Q006E012Q00024Q003A0003000200012Q00D93Q00013Q00023Q00023Q00030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500063Q0012443Q00013Q00206Q00024Q00029Q0000029Q008Q00017Q00023Q0003093Q00777269746566696C65030B3Q00434F4E4649475F46494C4500053Q0012C53Q00013Q00122Q000100026Q00029Q00000200016Q00017Q00043Q0003133Q0073617665436F6E6669675363686564756C656403043Q007461736B03053Q0064656C6179026Q00D03F000C3Q0012023Q00013Q00062D3Q000400013Q0004A13Q000400012Q00D93Q00014Q000D012Q00013Q0012683Q00013Q0012023Q00023Q00203F014Q000300124D2Q0100043Q00024700026Q00DF3Q000200012Q00D93Q00013Q00013Q00023Q0003133Q0073617665436F6E6669675363686564756C6564030A3Q0073617665436F6E66696700054Q00467Q00124Q00013Q00124Q00028Q000100016Q00017Q00073Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C65030B3Q0070656E64696E6753652Q6C001C3Q0012023Q00014Q00853Q0001000200062D3Q000900013Q0004A13Q000900010012023Q00023Q001202000100034Q0093012Q00020002000613012Q000B000100010004A13Q000B00012Q00358Q009D3Q00023Q0012023Q00043Q00024700016Q00A5012Q0002000100062D3Q001900013Q0004A13Q00190001001202000200054Q006E010300014Q009301020002000200262501020019000100060004A13Q0019000100203F01020001000700062D0002001900013Q0004A13Q001900012Q009D000100024Q0035000200024Q009D000200024Q00D93Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030F3Q0053452Q4C5F53544154455F46494C4500083Q001234012Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00023Q00030D3Q006C6F616453652Q6C53746174652Q00083Q0012023Q00014Q00853Q00010002002625012Q0005000100020004A13Q000500012Q00408Q000D012Q00014Q009D3Q00024Q00D93Q00017Q00093Q0003103Q0063616E557365436F6E66696746696C65030B3Q0070656E64696E6753652Q6C2Q0103053Q00706861736503063Q006D616E75616C030A3Q00726573756D654661726D03073Q007361766564417403043Q007469636B03053Q007063612Q6C02203Q0006132Q010004000100010004A13Q000400012Q000B00026Q006E2Q0100023Q001202000200014Q008500020001000200061301020009000100010004A13Q000900012Q00D93Q00014Q000B00023Q0005003021010200020003001099010200043Q00203F01030001000500261001030010000100030004A13Q001000012Q004000036Q000D010300013Q00109901020005000300203F01030001000600261001030016000100030004A13Q001600012Q004000036Q000D010300013Q00107F00020006000300122Q000300086Q00030001000200102Q00020007000300122Q000300093Q00064100043Q000100012Q006E012Q00024Q003A0003000200012Q00D93Q00013Q00013Q00043Q0003093Q00777269746566696C65030F3Q0053452Q4C5F53544154455F46494C45030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500083Q0012E23Q00013Q00122Q000100023Q00122Q000200033Q00202Q0002000200044Q00048Q000200049Q0000016Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503053Q007063612Q6C00093Q0012023Q00014Q00853Q00010002000613012Q0005000100010004A13Q000500012Q00D93Q00013Q0012023Q00023Q00024700016Q003A3Q000200012Q00D93Q00013Q00013Q00073Q0003063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503093Q00777269746566696C65030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465030B3Q0070656E64696E6753652Q6C012Q000E3Q0012023Q00013Q001202000100024Q0093012Q0002000200062D3Q000D00013Q0004A13Q000D00010012023Q00033Q00126F000100023Q00122Q000200043Q00202Q0002000200054Q00043Q000100302Q0004000600074Q000200049Q0000012Q00D93Q00017Q00013Q0003053Q007063612Q6C01093Q000613012Q0004000100010004A13Q000400012Q000B00016Q006E012Q00013Q001202000100013Q00064100023Q000100012Q006E017Q003A0001000200012Q00D93Q00013Q00013Q00083Q0003053Q00666F72636503153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003153Q006C6F674661726D53652Q73696F6E446973636F726403213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B0023Q00E081386E4103103Q00446973636F72644C6F674F6E53652Q6C00184Q00817Q00203F014Q000100062D3Q001000013Q0004A13Q001000010012023Q00023Q00062D3Q001700013Q0004A13Q001700010012023Q00034Q00853Q00010002002610012Q0017000100040004A13Q001700010012023Q00053Q00124D2Q0100063Q00124D010200074Q00DF3Q000200010004A13Q001700010012023Q00083Q00062D3Q001700013Q0004A13Q001700010012023Q00053Q00124D2Q0100063Q00124D010200074Q00DF3Q000200012Q00D93Q00017Q00053Q00030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F67030A3Q00726573756D654661726D03043Q007461736B03053Q006465666572020E3Q00120B010200016Q00020001000100122Q000200026Q00038Q00020002000100202Q00023Q000300062Q0002000C00013Q0004A13Q000C0001001202000200043Q00203F01020002000500024700036Q003A0002000200012Q009D000100024Q00D93Q00013Q00013Q00043Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D00113Q0012023Q00013Q000613012Q0010000100010004A13Q001000012Q000D012Q00013Q0012683Q00023Q0012023Q00033Q00062D3Q000C00013Q0004A13Q000C00010012023Q00034Q000D2Q0100014Q000D010200014Q00DF3Q000200012Q000D016Q0012683Q00023Q0012023Q00044Q0047012Q000100012Q00D93Q00017Q00063Q0003063Q00697061697273030A3Q0053452Q4C5F4954454D5303103Q0073652Q6C5265736F757263654974656D029A5Q99B93F03043Q007461736B03043Q0077616974022B4Q001900025Q00122Q000300013Q00122Q000400026Q00030002000500044Q0027000100062D0001000C00013Q0004A13Q000C00012Q006E010800014Q00850008000100020006130108000C000100010004A13Q000C00010004A13Q00290001001202000800034Q006E010900074Q009301080002000200062D0008001200013Q0004A13Q001200012Q000D010200013Q001202000800024Q0068010800083Q0006D80006001F000100080004A13Q001F000100062D3Q001F00013Q0004A13Q001F00012Q006E01085Q00124D010900044Q009301080002000200061301080027000100010004A13Q002700010004A13Q002900010004A13Q00270001001202000800024Q0068010800083Q0006D800060027000100080004A13Q00270001001202000800053Q00203F01080008000600124D010900044Q003A00080002000100065500030005000100020004A13Q000500012Q009D000200024Q00D93Q00017Q00033Q00030D3Q006C6F616453652Q6C537461746503043Q007461736B03053Q00737061776E000E3Q0012023Q00014Q00853Q00010002000613012Q0006000100010004A13Q000600012Q000D2Q016Q009D000100023Q001202000100023Q00203F2Q010001000300064100023Q000100012Q006E017Q003A0001000200012Q000D2Q0100014Q009D000100024Q00D93Q00013Q00013Q001D3Q00030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0073652Q6C03053Q00666F72636503063Q006D616E75616C2Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303053Q007068617365032A3Q00D092D0BED0B7D0BED0B1D0BDD0BED0B2D0BBD18FD0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E03133Q0077616974466F72436861726163746572487270026Q00284003043Q007461736B03043Q007761697403123Q0053452Q4C5F574149545F41465445525F545003203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D73030D3Q007361766553652Q6C537461746503063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q00776F726C6454656C65706F7274030D3Q004641524D5F574F524C445F4944027Q0040030D3Q006C6F616453652Q6C537461746503123Q0066696E616C697A6553652Q6C526573756D6503243Q00D097D0B0D0B2D0B5D180D188D0B0D0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E026Q00F03F030E3Q00636C65617253652Q6C537461746503043Q0069646C6500673Q0012023Q00013Q00062D3Q000400013Q0004A13Q000400012Q00D93Q00014Q000D012Q00013Q0012133Q00013Q00124Q00033Q00124Q00029Q0000034Q00015Q00202Q00010001000500262Q0001000E000100060004A13Q000E00012Q004000016Q000D2Q0100013Q001099012Q000400012Q008100015Q00203F2Q01000100070026102Q010015000100060004A13Q001500012Q004000016Q000D2Q0100013Q001099012Q0007000100024700015Q001099012Q0008000100064100010001000100012Q006E017Q008100025Q00203F0102000200090026250102004D000100030004A13Q004D00012Q006E010200013Q0012440103000A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q00020002000100122Q0002000D3Q00202Q00020002000E00122Q0003000F6Q0002000200014Q000200013Q00122Q000300106Q00020002000100122Q000200113Q000247000300023Q000247000400034Q005A00020004000200122Q000300123Q00122Q000400136Q00058Q0003000500014Q000300013Q00122Q000400146Q00030002000100122Q000300153Q00122Q000400166Q00030002000100122Q0003000B3Q00122Q0004000C6Q00030002000100122Q0003000D3Q00202Q00030003000E00122Q000400176Q00030002000100122Q000300186Q00030001000200062Q0003006200013Q0004A13Q0062000100203F01040003000900262501040062000100130004A13Q00620001001202000400194Q006E01056Q006E010600024Q00DF0004000600010004A13Q006200012Q008100025Q00203F01020002000900262501020060000100130004A13Q006000012Q006E010200013Q0012100003001A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q00020002000100120A0102000D3Q00202Q00020002000E00122Q0003001B6Q00020002000100122Q000200196Q00038Q000400016Q00020004000100044Q006200010012020002001C4Q00470102000100012Q000D01025Q001268000200013Q00124D0102001D3Q001268000200024Q00D93Q00013Q00043Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q001202000100013Q00062D0001000900013Q0004A13Q00090001001202000100013Q00203F2Q010001000200062D0001000900013Q0004A13Q00090001001202000100013Q0010992Q0100034Q00D93Q00017Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q008100015Q00203F2Q010001000100062D0001000900013Q0004A13Q00090001001202000100024Q008100025Q00203F0102000200012Q006E01036Q00DF0001000300012Q00D93Q00017Q00023Q0003043Q007461736B03043Q007761697401073Q0012EC000100013Q00202Q0001000100024Q00028Q0001000200014Q000100016Q000100028Q00017Q00013Q00030E3Q0073652Q6C496E50726F6772652Q7300033Q0012023Q00014Q009D3Q00024Q00D93Q00017Q003A3Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030B3Q00434F4E4649475F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C6503093Q004661726D54722Q657300030A3Q004661726D53746F6E6573030E3Q0054656C65706F727448656967687403063Q006E756D62657203133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A6503043Q006D61746803053Q00636C616D7003053Q00666C2Q6F72026Q003440026Q005E4003113Q00426C6F636B65645A6F6E6543656E746572026Q00084003073Q00566563746F72332Q033Q006E6577026Q00F03F027Q0040030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03063Q00737472696E6703153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F70030A3Q0055694C616E677561676503053Q006C6F77657203023Q00656E03023Q00727503083Q005569595363616C65030A3Q0073617665645569506F7303053Q005544696D3203083Q005569585363616C65028Q0003093Q005569584F2Q66736574026Q00304003093Q005569594F2Q6673657400E53Q0012023Q00014Q00853Q0001000200062D3Q000900013Q0004A13Q000900010012023Q00023Q001202000100034Q0093012Q00020002000613012Q000A000100010004A13Q000A00012Q00D93Q00013Q0012023Q00043Q00024700016Q00A5012Q0002000100062D3Q001400013Q0004A13Q00140001001202000200054Q006E010300014Q009301020002000200261001020015000100060004A13Q001500012Q00D93Q00013Q00203F0102000100070026250102001B000100080004A13Q001B000100203F0102000100090026100102001B000100080004A13Q001B0001001202000200053Q00203F01030001000A2Q0093010200020002002625010200220001000B0004A13Q0022000100203F01020001000A0012680002000A3Q001202000200053Q00203F01030001000C2Q0093010200020002002625010200290001000B0004A13Q0029000100203F01020001000C0012680002000C3Q00203F01020001000D0026100102002E000100080004A13Q002E000100203F01020001000D0012680002000D3Q00203F01020001000E00261001020033000100080004A13Q0033000100203F01020001000E0012680002000E3Q00203F01020001000F00261001020038000100080004A13Q0038000100203F01020001000F0012680002000F3Q00203F0102000100100026100102003D000100080004A13Q003D000100203F010200010010001268000200103Q001202000200053Q00203F0103000100112Q0093010200020002002625010200440001000B0004A13Q0044000100203F010200010011001268000200113Q001202000200053Q00203F0103000100122Q00930102000200020026250102004B0001000B0004A13Q004B000100203F010200010012001268000200123Q00203F01020001001300261001020050000100080004A13Q0050000100203F010200010013001268000200133Q00203F01020001001400261001020055000100080004A13Q0055000100203F010200010014001268000200143Q00203F0102000100150026100102005A000100080004A13Q005A000100203F010200010015001268000200153Q00203F0102000100160026100102005F000100080004A13Q005F000100203F010200010016001268000200163Q00203F01020001001700261001020064000100080004A13Q0064000100203F010200010017001268000200173Q00203F01020001001800261001020069000100080004A13Q0069000100203F010200010018001268000200183Q001202000200053Q00203F0103000100192Q0093010200020002002625010200780001000B0004A13Q007800010012020002001A3Q0020AC00020002001B00122Q0003001A3Q00202Q00030003001C00202Q0004000100194Q00030002000200122Q0004001D3Q00122Q0005001E6Q00020005000200122Q000200193Q001202000200053Q00203F01030001001F2Q00930102000200020026250102008B000100060004A13Q008B000100203F01020001001F2Q0068010200023Q000E640020008B000100020004A13Q008B0001001202000200213Q00209900020002002200202Q00030001001F00202Q00030003002300202Q00040001001F00202Q00040004002400202Q00050001001F00202Q0005000500204Q00020005000200122Q0002001F3Q00203F01020001002500261001020090000100080004A13Q0090000100203F010200010025001268000200253Q001202000200053Q00203F0103000100262Q0093010200020002002625010200970001000B0004A13Q0097000100203F010200010026001268000200263Q001202000200053Q00203F0103000100272Q00930102000200020026250102009E000100280004A13Q009E000100203F010200010027001268000200273Q00203F010200010029002610010200A3000100080004A13Q00A3000100203F010200010029001268000200293Q001202000200053Q00203F01030001002A2Q0093010200020002002625010200B50001000B0004A13Q00B500010012020002001A3Q0020FA00020002001B00122Q0003001A3Q00202Q00030003001C00202Q00040001002A4Q00030002000200122Q000400233Q00122Q0005001E6Q00020005000200122Q0002002A3Q00122Q0002002A3Q00202Q00020002002C00122Q0002002B3Q00203F01020001002D002610010200BA000100080004A13Q00BA000100203F01020001002D0012680002002D3Q00203F01020001002E002610010200BF000100080004A13Q00BF000100203F01020001002E0012680002002E3Q001202000200053Q00203F01030001002F2Q0093010200020002002625010200CE000100280004A13Q00CE000100203F01020001002F00202C0102000200302Q0093010200020002002625010200CC000100310004A13Q00CC000100124D010200313Q000613010200CD000100010004A13Q00CD000100124D010200323Q0012680002002F3Q001202000200053Q00203F0103000100332Q0093010200020002002625010200E40001000B0004A13Q00E40001001202000200353Q00203F01020002002200203F010300010036000613010300D9000100010004A13Q00D9000100124D010300373Q00203F010400010038000613010400DD000100010004A13Q00DD000100124D010400393Q00203F01050001003300203F01060001003A000613010600E2000100010004A13Q00E2000100124D010600374Q00A3010200060002001268000200344Q00D93Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030B3Q00434F4E4649475F46494C4500083Q001234012Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00043Q0003043Q007469636B030D3Q006C6173745761726E696E674174025Q00804640030C3Q006661726D5761726E696E677302113Q001256010200016Q00020001000200122Q000300026Q000300033Q00062Q0003000C00013Q0004A13Q000C0001001202000300024Q00C3000300034Q007301030002000300263A0103000C000100030004A13Q000C00012Q00D93Q00013Q001202000300024Q007200033Q0002001202000300044Q007200033Q00012Q00D93Q00017Q00023Q00030C3Q006661726D5761726E696E67730001033Q001202000100013Q0020DA00013Q00022Q00D93Q00017Q00083Q0003053Q007061697273030C3Q006661726D5761726E696E677303053Q007461626C6503063Q00696E7365727403043Q00E280A22003043Q00736F727403063Q00636F6E63617403013Q000A00194Q00E07Q00122Q000100013Q00122Q000200026Q00010002000300044Q000C0001001202000600033Q00201A0106000600044Q00075Q00122Q000800056Q000900056Q0008000800094Q00060008000100065500010005000100020004A13Q00050001001202000100033Q0020B10001000100064Q00028Q00010002000100122Q000100033Q00202Q0001000100074Q00025Q00122Q000300086Q000100036Q00019Q0000017Q00033Q0003053Q0073746F6E6503133Q0053746F6E6554656C65706F7274486569676874030E3Q0054656C65706F727448656967687401073Q002625012Q0004000100010004A13Q00040001001202000100024Q009D000100023Q001202000100034Q009D000100024Q00D93Q00017Q00073Q00030F3Q0063616368656454722Q65436F756E74028Q0003013Q004C030A3Q006D6F64655F74722Q657303103Q0063616368656453746F6E65436F756E74030B3Q006D6F64655F73746F6E6573030B3Q006D6F64655F73656172636800133Q0012023Q00013Q000EDD0002000700013Q0004A13Q000700010012023Q00033Q00124D2Q0100044Q002E3Q00014Q003D016Q0012023Q00053Q000EDD0002000E00013Q0004A13Q000E00010012023Q00033Q00124D2Q0100064Q002E3Q00014Q003D016Q0012023Q00033Q00124D2Q0100074Q002E3Q00014Q003D017Q00D93Q00017Q00033Q0003123Q0055736572446973636F7264576562682Q6F6B034Q00030B3Q004B45595F574542482Q4F4B000B3Q0012023Q00013Q00062D3Q000800013Q0004A13Q000800010012023Q00013Q002610012Q0008000100020004A13Q000800010012023Q00014Q009D3Q00023Q0012023Q00034Q009D3Q00024Q00D93Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503123Q007363686564756C6553617665436F6E66696700083Q0012023Q00014Q00853Q00010002000613012Q0005000100010004A13Q000500012Q00D93Q00013Q0012023Q00024Q0047012Q000100012Q00D93Q00017Q000D3Q0003093Q004C6F63616C654C6962031C3Q006D6178692D6875622F6D6178692D6875622D6C6F63616C652E6C756103133Q006D6178692D6875622D6C6F63616C652E6C756103063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503063Q00697061697273030A3Q006C6F6164737472696E6703143Q00406D6178692D6875622D6C6F63616C652E6C756103053Q007063612Q6C03043Q007479706503053Q007461626C6500363Q0012023Q00013Q00062D3Q000500013Q0004A13Q000500010012023Q00014Q009D3Q00024Q000B3Q00023Q00124D2Q0100023Q00124D010200034Q001D3Q00020001001202000100043Q001202000200054Q00932Q01000200020026252Q010033000100060004A13Q00330001001202000100043Q001202000200074Q00932Q01000200020026252Q010033000100060004A13Q00330001001202000100084Q006E01026Q00A52Q01000200030004A13Q00310001001202000600074Q006E010700054Q009301060002000200062D0006003100013Q0004A13Q00310001001202000600093Q0012AD000700056Q000800056Q00070002000200122Q0008000A6Q00060008000200062Q0006003100013Q0004A13Q003100010012020007000B4Q006E010800064Q00A501070002000800062D0007003100013Q0004A13Q003100010012020009000C4Q006E010A00084Q0093010900020002002625010900310001000D0004A13Q00310001001268000800013Q001202000900014Q009D000900023Q00065500010017000100020004A13Q001700012Q0035000100014Q009D000100024Q00D93Q00017Q00053Q0003093Q004C6F63616C654C696203063Q00747970656F6603013Q007403083Q0066756E6374696F6E030A3Q0055694C616E677561676501113Q001202000100013Q00062D0001000F00013Q0004A13Q000F0001001202000100023Q001202000200013Q00203F0102000200032Q00932Q01000200020026252Q01000F000100040004A13Q000F0001001202000100013Q00209D2Q010001000300122Q000200056Q00038Q000100036Q00016Q009D3Q00024Q00D93Q00017Q00053Q0003053Q007461626C6503063Q00696E73657274030E3Q006C6F63616C6542696E64696E677303073Q00656C656D656E742Q033Q006B6579020C3Q00062D3Q000B00013Q0004A13Q000B000100062D0001000B00013Q0004A13Q000B0001001202000200013Q00208201020002000200122Q000300036Q00043Q000200102Q000400043Q00102Q0004000500014Q0002000400012Q00D93Q00017Q000C3Q0003043Q006E616D6503013Q004C03083Q007461625F686F6D6503053Q007469746C6503083Q007375627469746C65030C3Q007461625F686F6D655F737562030C3Q007461625F73652Q74696E677303103Q007461625F73652Q74696E67735F737562030B3Q007461625F646973636F7264030F3Q007461625F646973636F72645F737562030B3Q007461625F63726564697473030F3Q007461625F637265646974735F73756200384Q00173Q00046Q00013Q000300122Q000200023Q00122Q000300036Q00020002000200102Q00010001000200122Q000200023Q00122Q000300036Q00020002000200102Q00010004000200122Q000200023Q00122Q000300066Q00020002000200102Q0001000500024Q00023Q000300122Q000300023Q00122Q000400076Q00030002000200102Q00020001000300122Q000300023Q00122Q000400076Q00030002000200102Q00020004000300122Q000300023Q00122Q000400086Q00030002000200102Q0002000500034Q00033Q000300122Q000400023Q00122Q000500096Q00040002000200102Q00030001000400122Q000400023Q00122Q000500096Q00040002000200102Q00030004000400122Q000400023Q00122Q0005000A6Q00040002000200102Q0003000500044Q00043Q000300122Q000500023Q00122Q0006000B6Q00050002000200102Q00040001000500122Q000500023Q00122Q0006000B6Q00050002000200102Q00040004000500122Q000500023Q00122Q0006000C6Q00050002000200102Q0004000500056Q000400012Q009D3Q00024Q00D93Q00017Q00103Q00030A3Q0050484153455F5445585403043Q0069646C6503013Q004C030A3Q0070686173655F69646C6503063Q00736561726368030C3Q0070686173655F73656172636803043Q006D696E65030A3Q0070686173655F6D696E6503043Q0077616974030A3Q0070686173655F7761697403073Q00636F2Q6C656374030D3Q0070686173655F636F2Q6C65637403043Q0073652Q6C030A3Q0070686173655F73652Q6C2Q033Q0068756203093Q0070686173655F687562001F4Q009F014Q000700122Q000100033Q00122Q000200046Q00010002000200104Q0002000100122Q000100033Q00122Q000200066Q00010002000200104Q0005000100122Q000100033Q00122Q000200086Q00010002000200104Q0007000100122Q000100033Q00122Q0002000A6Q00010002000200104Q0009000100122Q000100033Q00122Q0002000C6Q00010002000200104Q000B000100122Q000100033Q00122Q0002000E6Q00010002000200104Q000D000100122Q000100033Q00122Q000200106Q00010002000200104Q000F000100124Q00018Q00017Q00063Q00030D3Q00646973636F726453746174757303043Q005465787403103Q0063616E557365436F6E66696746696C6503013Q004C03103Q00776562682Q6F6B5F73617665645F6F6B03113Q00776562682Q6F6B5F73617665645F62616400133Q0012023Q00013Q000613012Q0004000100010004A13Q000400012Q00D93Q00013Q0012023Q00013Q001202000100034Q008500010001000200062D0001000E00013Q0004A13Q000E0001001202000100043Q00124D010200054Q00932Q01000200020006132Q010011000100010004A13Q00110001001202000100043Q00124D010200064Q00932Q0100020002001099012Q000200012Q00D93Q00017Q00073Q0003113Q006372656469747341626F75744C6162656C03043Q0054657874030C3Q005343524950545F5449544C4503013Q000A03013Q004C030B3Q007363726970745F6C696E65030E3Q00637265646974735F7468616E6B7301133Q001202000100013Q0006132Q010004000100010004A13Q000400012Q00D93Q00013Q001202000100013Q001202000200033Q00124D010300043Q0006330104000C00013Q0004A13Q000C0001001202000400053Q00124D010500064Q009301040002000200124D010500043Q001262010600053Q00122Q000700076Q0006000200024Q00020002000600102Q0001000200026Q00017Q00223Q0003063Q00697061697273030E3Q006C6F63616C6542696E64696E677303073Q00656C656D656E7403063Q00506172656E7403043Q005465787403013Q004C2Q033Q006B657903103Q007265667265736850686173655465787403173Q00757064617465446973636F72645374617475735465787403163Q007570646174654372656469747341626F757454657874030D3Q006D616E75616C53652Q6C42746E030B3Q0062746E5F73652Q6C696E67030C3Q0062746E5F73652Q6C5F6E6F77030F3Q0063726564697473546742752Q746F6E03093Q0074675F636F7069656403093Q0074675F62752Q746F6E030C3Q007A6F6E65506C61636542746E030F3Q0062746E5F637562655F706C6163656403103Q0062746E5F6E6F5F636861726163746572030E3Q0062746E5F706C6163655F6375626503023Q00756903063Q00747970656F66030C3Q007365745469746C6548696E7403083Q0066756E6374696F6E030A3Q007469746C655F68696E74030F3Q007365744869646548696E745465787403093Q00686964655F68696E7403103Q00726566726573685461624C6162656C73030A3Q0067657454616244656673030B3Q007365744C616E6775616765030A3Q0055694C616E677561676503103Q00726566726573684B657953746174757303043Q0067656E76030E3Q004D6178694875624B65794761746500923Q0012023Q00013Q001202000100024Q00A5012Q000200020004A13Q0010000100203F01050004000300062D0005001000013Q0004A13Q0010000100203F01050004000300203F01050005000400062D0005001000013Q0004A13Q0010000100203F010500040003001202000600063Q00203F0107000400072Q00930106000200020010990105000500060006553Q0004000100020004A13Q000400010012023Q00084Q00933Q0001000100124Q00098Q0001000100124Q000A8Q0001000100124Q000B3Q00064Q002700013Q0004A13Q002700010012023Q000B3Q002055014Q000500122Q000100063Q00122Q0002000C6Q00010002000200064Q0027000100010004A13Q002700010012023Q000B3Q001202000100063Q00124D0102000D4Q00932Q0100020002001099012Q000500010012023Q000E3Q00062D3Q003600013Q0004A13Q003600010012023Q000E3Q002055014Q000500122Q000100063Q00122Q0002000F6Q00010002000200064Q0036000100010004A13Q003600010012023Q000E3Q001202000100063Q00124D010200104Q00932Q0100020002001099012Q000500010012023Q00113Q00062D3Q004C00013Q0004A13Q004C00010012023Q00113Q002055014Q000500122Q000100063Q00122Q000200126Q00010002000200064Q004C000100010004A13Q004C00010012023Q00113Q002055014Q000500122Q000100063Q00122Q000200136Q00010002000200064Q004C000100010004A13Q004C00010012023Q00113Q001202000100063Q00124D010200144Q00932Q0100020002001099012Q000500010012023Q00153Q00062D3Q008500013Q0004A13Q008500010012023Q00163Q001202000100153Q00203F2Q01000100172Q0093012Q00020002002625012Q005B000100180004A13Q005B00010012023Q00153Q0020E45Q001700122Q000100063Q00122Q000200196Q000100029Q0000010012023Q00163Q001202000100153Q00203F2Q010001001A2Q0093012Q00020002002625012Q0067000100180004A13Q006700010012023Q00153Q0020E45Q001A00122Q000100063Q00122Q0002001B6Q000100029Q0000010012023Q00163Q001202000100153Q00203F2Q010001001C2Q0093012Q00020002002625012Q0072000100180004A13Q007200010012023Q00153Q00203F014Q001C0012020001001D4Q00392Q0100014Q00275Q00010012023Q00163Q001202000100153Q00203F2Q010001001E2Q0093012Q00020002002625012Q007C000100180004A13Q007C00010012023Q00153Q00203F014Q001E0012020001001F4Q003A3Q000200010012023Q00163Q001202000100153Q00203F2Q01000100202Q0093012Q00020002002625012Q0085000100180004A13Q008500010012023Q00153Q00203F014Q00202Q0047012Q000100010012023Q00213Q00203F014Q002200062D3Q009100013Q0004A13Q00910001001202000100163Q00203F01023Q001E2Q00932Q01000200020026252Q010091000100180004A13Q0091000100203F2Q013Q001E0012020002001F4Q003A0001000200012Q00D93Q00017Q00083Q00030A3Q0055694C616E677561676503043Q007479706503063Q00737472696E6703053Q006C6F77657203023Q00656E03023Q00727503123Q00612Q706C794D6178694875624C6F63616C6503123Q007363686564756C6553617665436F6E66696701133Q001202000100024Q006E01026Q00932Q01000200020026252Q01000C000100030004A13Q000C000100202C2Q013Q00042Q00932Q01000200020026252Q01000C000100050004A13Q000C000100124D2Q0100053Q0006132Q01000D000100010004A13Q000D000100124D2Q0100063Q001268000100013Q00121C000100076Q00010001000100122Q000100086Q0001000100016Q00017Q00093Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030E3Q00576F726C6454656C65706F727473030B3Q0054656C65706F7274506164030D3Q0054656C65706F72744D6F64656C2Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734100293Q0012B83Q00013Q00206Q000200122Q000200038Q0002000200064Q0008000100010004A13Q000800012Q0035000100014Q009D000100023Q00202C2Q013Q000200124D010300044Q00A32Q01000300020006132Q01000F000100010004A13Q000F00012Q0035000200024Q009D000200023Q00202C01020001000200124D010400054Q00A301020004000200061301020016000100010004A13Q001600012Q0035000300034Q009D000300023Q00202C01030002000200124D010500064Q00A30103000500020006130103001D000100010004A13Q001D00012Q0035000400044Q009D000400023Q00202C01040003000700124D010600084Q00A301040006000200062D0004002300013Q0004A13Q002300012Q009D000300023Q00202C0104000300090012BE000600086Q000700016Q000400076Q00049Q0000017Q00033Q0003133Q005669727475616C496E7075744D616E6167657203043Q0067616D65030A3Q004765745365727669636500063Q0012153Q00023Q00206Q000300122Q000200018Q0002000200124Q00018Q00017Q00023Q0003133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00073Q0012023Q00013Q00062D3Q000600013Q0004A13Q000600010012023Q00023Q00024700016Q003A3Q000200012Q00D93Q00013Q00013Q00063Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D65000A3Q0012A03Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00033Q0003093Q006D6F75736548656C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00103Q0012023Q00013Q000613012Q0004000100010004A13Q000400012Q00D93Q00013Q0012023Q00023Q00062D3Q000A00013Q0004A13Q000A00010012023Q00033Q00024700016Q003A3Q000200010012023Q00033Q000247000100014Q003A3Q000200012Q000D016Q0012683Q00014Q00D93Q00013Q00023Q00063Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F75736559028Q0003043Q0067616D65000A3Q001241012Q00013Q00206Q000200122Q000200033Q00122Q000300043Q00122Q000400056Q00055Q00122Q000600063Q00122Q000700058Q000700016Q00017Q00033Q0003063Q00747970656F66030D3Q006D6F7573653172656C6561736503083Q0066756E6374696F6E00083Q0012023Q00013Q001202000100024Q0093012Q00020002002625012Q0007000100030004A13Q000700010012023Q00024Q0047012Q000100012Q00D93Q00017Q00083Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900133Q0012023Q00013Q00203F014Q000200062D3Q000900013Q0004A13Q000900010012023Q00013Q00203F014Q000200202C014Q000300124D010200044Q00A3012Q00020002000613012Q000C000100010004A13Q000C00012Q00D93Q00013Q001202000100063Q00205F00010001000700104Q0005000100122Q000100063Q00202Q00010001000700104Q000800016Q00017Q00023Q00030F3Q00426C6F636B65645A6F6E6553697A65027Q004000043Q0012023Q00013Q0020A2014Q00022Q009D3Q00024Q00D93Q00017Q00043Q0003113Q00426C6F636B65645A6F6E6543656E74657203163Q00676574426C6F636B65645A6F6E6548616C6653697A6503073Q00566563746F72332Q033Q006E657700193Q0012023Q00013Q000613012Q0005000100010004A13Q000500012Q00353Q00014Q008C3Q00033Q0012023Q00024Q00BB3Q0001000200122Q000100013Q00122Q000200033Q00202Q0002000200044Q00038Q00048Q00058Q0002000500024Q00010001000200122Q000200013Q001202000300033Q00208C0103000300044Q00048Q00058Q00068Q0003000600024Q0002000200034Q000100038Q00017Q00063Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403113Q00426C6F636B65645A6F6E6543656E74657203143Q00676574426C6F636B65645A6F6E654D696E4D617803013Q005803013Q005903013Q005A012E3Q001202000100013Q00062D0001000800013Q0004A13Q0008000100062D3Q000800013Q0004A13Q00080001001202000100023Q0006132Q01000A000100010004A13Q000A00012Q000D2Q016Q009D000100023Q001202000100034Q00A12Q010001000200062D0001001000013Q0004A13Q0010000100061301020012000100010004A13Q001200012Q000D01036Q009D000300023Q00203F01033Q000400203F01040001000400062F0004002A000100030004A13Q002A000100203F01033Q000400203F01040002000400062F0003002A000100040004A13Q002A000100203F01033Q000500203F01040001000500062F0004002A000100030004A13Q002A000100203F01033Q000500203F01040002000500062F0003002A000100040004A13Q002A000100203F01033Q000600203F01040001000600062F0004002A000100030004A13Q002A000100203F01033Q000600203F0104000200060006A200030002000100040004A13Q002B00012Q004000036Q000D010300014Q009D000300024Q00D93Q00017Q00023Q00030D3Q006765744E6F646543656E74657203123Q006973506F73496E426C6F636B65645A6F6E65010A3Q001202000100014Q006E01026Q00932Q010002000200063D00020008000100010004A13Q00080001001202000200024Q006E010300014Q00930102000200022Q009D000200024Q00D93Q00017Q00083Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203083Q00496E7374616E63652Q033Q006E657703063Q00466F6C64657203043Q004E616D6503063Q00506172656E7400113Q001208012Q00013Q00206Q000200122Q000200038Q0002000200064Q000F000100010004A13Q000F0001001202000100043Q00202F2Q010001000500122Q000200066Q0001000200026Q00013Q00122Q000100033Q00104Q0007000100122Q000100013Q00104Q000800012Q009D3Q00024Q00D93Q00017Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403053Q007063612Q6C000C3Q0012023Q00013Q00062D3Q000800013Q0004A13Q000800010012023Q00023Q00024700016Q003A3Q000200012Q00357Q0012683Q00013Q0012023Q00023Q000247000100014Q003A3Q000200012Q00D93Q00013Q00023Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403073Q0044657374726F7900043Q0012023Q00013Q00202C014Q00022Q003A3Q000200012Q00D93Q00017Q00043Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203073Q0044657374726F7900093Q0012EA3Q00013Q00206Q000200122Q000200038Q0002000200064Q000800013Q0004A13Q0008000100202C2Q013Q00042Q003A0001000200012Q00D93Q00017Q00203Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403113Q00426C6F636B65645A6F6E6543656E74657203183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203153Q00626C6F636B65645A6F6E6556697375616C5061727403063Q00506172656E7403083Q00496E7374616E63652Q033Q006E657703043Q005061727403043Q004E616D65030A3Q00416E746954505A6F6E6503083Q00416E63686F7265642Q01030A3Q0043616E436F2Q6C696465010003083Q0043616E517565727903083Q0043616E546F756368030A3Q0043617374536861646F7703083Q004D6174657269616C03043Q00456E756D030A3Q00466F7263654669656C6403053Q00436F6C6F7203063Q00436F6C6F723303073Q0066726F6D524742025Q00E06F40025Q00805140030C3Q005472616E73706172656E6379020AD7A3703D0AE73F03043Q0053697A6503073Q00566563746F7233030F3Q00426C6F636B65645A6F6E6553697A6503063Q00434672616D6500453Q0012023Q00013Q00062D3Q000600013Q0004A13Q000600010012023Q00023Q000613012Q0009000100010004A13Q000900010012023Q00034Q0047012Q000100012Q00D93Q00013Q0012023Q00044Q00853Q00010002001202000100053Q00062D0001001200013Q0004A13Q00120001001202000100053Q00203F2Q01000100060006132Q010034000100010004A13Q00340001001202000100073Q0020962Q010001000800122Q000200096Q00010002000200122Q000100053Q00122Q000100053Q00302Q0001000A000B00122Q000100053Q00302Q0001000C000D00122Q000100053Q00302Q0001000E000F00122Q000100053Q00302Q00010010000F00122Q000100053Q00302Q00010011000F00122Q000100053Q00302Q00010012000F00122Q000100053Q00122Q000200143Q00202Q00020002001300202Q00020002001500102Q00010013000200122Q000100053Q00122Q000200173Q00202Q00020002001800122Q000300193Q00122Q0004001A3Q00122Q0005001A6Q00020005000200102Q00010016000200122Q000100053Q00302Q0001001B001C00122Q000100053Q00102Q000100063Q001202000100053Q00126B0002001E3Q00202Q00020002000800122Q0003001F3Q00122Q0004001F3Q00122Q0005001F6Q00020005000200102Q0001001D000200122Q000100053Q00122Q000200203Q00202Q00020002000800122Q000300026Q00020002000200102Q00010020000200122Q000100053Q00302Q0001001B001C6Q00017Q00083Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403113Q00426C6F636B65645A6F6E6543656E74657203083Q00506F736974696F6E03173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E66696700163Q0012023Q00013Q00203F014Q000200062D3Q000900013Q0004A13Q000900010012023Q00013Q00203F014Q000200202C014Q000300124D010200044Q00A3012Q00020002000613012Q000D000100010004A13Q000D00012Q000D2Q016Q009D000100023Q00203F2Q013Q00060012542Q0100053Q00122Q000100076Q00010001000100122Q000100086Q0001000100014Q000100016Q000100028Q00017Q000B3Q0003123Q006973506F73496E426C6F636B65645A6F6E6503063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403063Q00434672616D652Q033Q006E657703163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747901203Q001202000100014Q006E01026Q00932Q010002000200062D0001000600013Q0004A13Q000600012Q00D93Q00013Q001202000100023Q00203F2Q010001000300062D0001000F00013Q0004A13Q000F0001001202000100023Q00203F2Q010001000300202C2Q010001000400124D010300054Q00A32Q010003000200062D0001001300013Q0004A13Q00130001000613012Q0014000100010004A13Q001400012Q00D93Q00013Q001202000200063Q0020C90002000200074Q00038Q00020002000200102Q00010006000200122Q000200093Q00202Q00020002000A00102Q00010008000200122Q000200093Q00202Q00020002000A00102Q0001000B00026Q00017Q000A3Q0003043Q007469636B03123Q0073686F756C644661726D436F6E74696E756503043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F0002293Q001202000200014Q00850002000100022Q007C010200023Q001202000300014Q00850003000100020006D80003001F000100020004A13Q001F000100062D0001001000013Q0004A13Q00100001001202000300024Q006E010400014Q009301030002000200061301030010000100010004A13Q001000012Q000D01036Q009D000300023Q001202000300033Q00209E00030003000400122Q000400053Q00202Q00040004000600122Q000500073Q00122Q000600053Q00202Q00060006000800122Q000700093Q00122Q000800016Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q000300010026102Q0100260001000A0004A13Q00260001001202000300024Q006E010400014Q00930103000200020004A13Q002700012Q004000036Q000D010300014Q009D000300024Q00D93Q00017Q000A3Q00030F3Q006D616E75616C53652Q6C546F6B656E03043Q007469636B030E3Q0073652Q6C496E50726F6772652Q7303043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F01283Q001202000100013Q001202000200024Q00850002000100022Q007C010200023Q001202000300024Q00850003000100020006D80003001F000100020004A13Q001F0001001202000300013Q00065F2Q01000E000100030004A13Q000E0001001202000300033Q00061301030010000100010004A13Q001000012Q000D01036Q009D000300023Q001202000300043Q00209E00030003000500122Q000400063Q00202Q00040004000700122Q000500083Q00122Q000600063Q00202Q00060006000900122Q0007000A3Q00122Q000800026Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q00040001001202000300013Q00065F2Q010024000100030004A13Q00240001001202000300033Q0004A13Q002600012Q004000036Q000D010300014Q009D000300024Q00D93Q00017Q000B3Q0003143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274001F3Q0012023Q00014Q00853Q0001000200062D3Q000F00013Q0004A13Q000F000100203F2Q013Q00030012B4000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100023Q00122Q000100026Q000100023Q001202000100083Q00203F2Q010001000900062D0001001800013Q0004A13Q00180001001202000100083Q00203F2Q010001000900202C2Q010001000A00124D0103000B4Q00A32Q010003000200062D0001001E00013Q0004A13Q001E000100203F010200010003001268000200023Q001202000200024Q009D000200024Q00D93Q00017Q00123Q00030B3Q00687562506F736974696F6E03143Q0067657454656C65706F7274537061776E5061727403083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q0069706169727303053Q00537061776E030D3Q00537061776E4C6F636174696F6E2Q033Q0048756203093Q00776F726B7370616365030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734103123Q0063617074757265487562506F736974696F6E026Q00144000483Q0012023Q00013Q00062D3Q000500013Q0004A13Q000500010012023Q00014Q009D3Q00023Q0012023Q00024Q00853Q0001000200062D3Q001400013Q0004A13Q0014000100203F2Q013Q00030012B4000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100013Q00122Q000100016Q000100023Q001202000100084Q00F0000200033Q00122Q000300093Q00122Q0004000A3Q00122Q0005000B6Q0002000300012Q00A52Q01000200030004A13Q003A00010012020006000C3Q00202C01060006000D2Q006E010800054Q00A301060008000200062D0006003A00013Q0004A13Q003A000100202C01070006000E00124D0109000F4Q00A301070009000200062D0007002900013Q0004A13Q002900010006330107002D000100060004A13Q002D000100202C01070006001000124D0109000F4Q000D010A00014Q00A30107000A000200062D0007003A00013Q0004A13Q003A000100203F0108000700030012B4000900043Q00202Q00090009000500122Q000A00063Q00122Q000B00073Q00122Q000C00066Q0009000C00024Q00080008000900122Q000800013Q00122Q000800016Q000800023Q0006550001001C000100020004A13Q001C0001001202000100114Q00850001000100020006132Q010046000100010004A13Q00460001001202000100043Q0020B900010001000500122Q000200063Q00122Q000300123Q00122Q000400066Q0001000400022Q009D000100024Q00D93Q00017Q000D3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030E3Q00676574487562506F736974696F6E03073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030F3Q004855425F4E4541525F52414449555300283Q0012023Q00013Q00203F014Q000200062D3Q000900013Q0004A13Q000900010012023Q00013Q00203F014Q000200202C014Q000300124D010200044Q00A3012Q00020002001202000100054Q008500010001000200062D3Q000F00013Q0004A13Q000F00010006132Q010011000100010004A13Q001100012Q000D01026Q009D000200023Q001202000200063Q0020FE00020002000700202Q00033Q000800202Q00030003000900202Q00040001000A00202Q00053Q000800202Q00050005000B4Q00020005000200122Q000300063Q00202Q00030003000700202Q00040001000900202Q00050001000A00202Q00060001000B4Q0003000600024Q00040002000300202Q00040004000C00122Q0005000D3Q00062Q00040002000100050004A13Q002500012Q004000046Q000D010400014Q009D000400024Q00D93Q00017Q000A3Q0003093Q0069734E65617248756203143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q000840030D3Q0074656C65706F7274487270546F030E3Q00676574487562506F736974696F6E001B3Q0012023Q00014Q00853Q0001000200062D3Q000500013Q0004A13Q000500012Q00D93Q00013Q0012023Q00024Q00853Q0001000200062D3Q001600013Q0004A13Q0016000100203F2Q013Q0004001202000200053Q0020B900020002000600122Q000300073Q00122Q000400083Q00122Q000500076Q0002000500022Q000F00010001000200122Q000100033Q00122Q000100093Q00122Q000200036Q0001000200016Q00013Q001202000100093Q0012020002000A4Q0039010200014Q002700013Q00012Q00D93Q00017Q000E4Q0003093Q006661726D50686173652Q033Q0068756203103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q0063752Q72656E7454617267657450617274030D3Q0074656C65706F7274546F487562030E3Q0048756257616974456E61626C6564030C3Q004855425F574149545F4D494E03043Q006D61746803063Q0072616E646F6D030C3Q004855425F574149545F4D415803113Q00696E74652Q7275707469626C655761697402253Q0026252Q010003000100010004A13Q000300012Q000D2Q0100013Q00124D010200033Q001256000200023Q00122Q000200046Q00020001000100122Q000200056Q00020001000100122Q000200066Q0002000100014Q000200023Q00122Q000200073Q00062Q0001001100013Q0004A13Q00110001001202000200084Q0047010200010001001202000200093Q00061301020016000100010004A13Q001600012Q000D010200014Q009D000200023Q0012020002000A3Q0012900103000B3Q00202Q00030003000C4Q00030001000200122Q0004000D3Q00122Q0005000A6Q0004000400054Q0003000300044Q00020002000300122Q0003000E6Q000400026Q00058Q000300056Q00039Q0000017Q00033Q00030B3Q00687562526573745761697403093Q006661726D506861736503043Q0069646C65010C3Q001202000100014Q006E01026Q00932Q01000200020006132Q010007000100010004A13Q000700012Q000D2Q016Q009D000100023Q00124D2Q0100033Q001268000100024Q000D2Q0100014Q009D000100024Q00D93Q00017Q00023Q0003073Q00557365464B6579030B3Q006175746F4641637469766500063Q0012023Q00013Q000613012Q0004000100010004A13Q000400010012023Q00024Q009D3Q00024Q00D93Q00017Q00033Q00030C3Q0073686F756C645072652Q734603133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C000F3Q0012023Q00014Q00853Q00010002000613012Q0005000100010004A13Q000500012Q00D93Q00013Q0012023Q00023Q00062D3Q000B00013Q0004A13Q000B00010012023Q00033Q00024700016Q003A3Q000200010012023Q00033Q000247000100014Q003A3Q000200012Q00D93Q00013Q00023Q00093Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D6503043Q007461736B03043Q007761697402B81E85EB51B89E3F00173Q001261012Q00013Q00206Q00024Q000200013Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q0005000100124Q00073Q00206Q000800122Q000100098Q0002000100124Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00023Q0003063Q006B657974617003043Q00564B5F4600043Q0012023Q00013Q001202000100024Q003A3Q000200012Q00D93Q00017Q000A3Q00028Q0003093Q006D6F75736548656C6403043Q006D6174682Q033Q00616273030A3Q00686F6C644D6F75736558027Q0040030A3Q00686F6C644D6F7573655903103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C022D3Q0006330102000300013Q0004A13Q0003000100124D010200013Q0006132Q010006000100010004A13Q0006000100124D2Q0100014Q006E012Q00023Q001202000200023Q00062D0002001900013Q0004A13Q00190001001202000200033Q00204A00020002000400122Q000300056Q000300036Q00020002000200262Q00020019000100060004A13Q00190001001202000200033Q00204A00020002000400122Q000300076Q0003000300014Q00020002000200262Q00020019000100060004A13Q001900012Q00D93Q00013Q001202000200084Q0047010200010001001202000200093Q00062D0002002400013Q0004A13Q002400010012020002000A3Q00064100033Q000100022Q006E017Q006E012Q00014Q003A0002000200010004A13Q002700010012020002000A3Q000247000300014Q003A0002000200012Q000D010200013Q001248000200026Q00025Q00122Q000100073Q00122Q000200058Q00013Q00023Q00043Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D65000A3Q0012A4012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q000700016Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F757365317072652Q7303083Q0066756E6374696F6E00083Q0012023Q00013Q001202000100024Q0093012Q00020002002625012Q0007000100030004A13Q000700010012023Q00024Q0047012Q000100012Q00D93Q00017Q00033Q0003103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C02133Q001202000200014Q0047010200010001001202000200023Q00062D0002000F00013Q0004A13Q000F000100062D3Q000F00013Q0004A13Q000F000100062D0001000F00013Q0004A13Q000F0001001202000200033Q00064100033Q000100022Q006E017Q006E012Q00014Q003A0002000200010004A13Q00120001001202000200033Q000247000300014Q003A0002000200012Q00D93Q00013Q00023Q00073Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D6503043Q007461736B03043Q0077616974029A5Q99A93F00173Q00121A3Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q0007000100124Q00053Q00206Q000600122Q000100078Q0002000100124Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q00055Q00122Q000600043Q00122Q000700038Q000700016Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F75736531636C69636B03083Q0066756E6374696F6E00083Q0012023Q00013Q001202000100024Q0093012Q00020002002625012Q0007000100030004A13Q000700010012023Q00024Q0047012Q000100012Q00D93Q00017Q00073Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D65726103143Q00576F726C64546F56696577706F7274506F696E74030A3Q0047756953657276696365030B3Q00476574477569496E73657403013Q005803013Q005901163Q000613012Q0004000100010004A13Q000400012Q0035000100014Q009D000100023Q001202000100013Q00203F2Q01000100020006132Q01000A000100010004A13Q000A00012Q0035000200024Q009D000200023Q00202C0102000100032Q000900048Q00020004000200122Q000300043Q00202Q0003000300054Q00030002000200202Q00040002000600202Q00050002000700202Q0006000300074Q0005000500064Q000400034Q00D93Q00017Q00083Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D657261030A3Q0047756953657276696365030B3Q00476574477569496E736574030C3Q0056696577706F727453697A6503013Q0058026Q00E03F03013Q005900123Q0012023Q00013Q00203F014Q0002000613012Q0006000100010004A13Q000600012Q0035000100014Q009D000100023Q001202000100033Q0020690001000100044Q00010002000200202Q00023Q000500202Q00030002000600202Q00030003000700202Q00040002000800202Q00040004000700202Q0005000100084Q0004000400054Q000300034Q00D93Q00017Q00043Q002Q033Q0049734103083Q00426173655061727403083Q00506F736974696F6E03163Q0046696E6446697273744368696C64576869636849734101143Q000613012Q0004000100010004A13Q000400012Q0035000100014Q009D000100023Q00202C2Q013Q000100124D010300024Q00A32Q010003000200062D0001000B00013Q0004A13Q000B000100203F2Q013Q00032Q009D000100023Q00202C2Q013Q000400124D010300024Q000D010400014Q00A32Q010004000200062D0001001300013Q0004A13Q0013000100203F0102000100032Q009D000200024Q00D93Q00017Q00063Q00030F3Q0067657450617274506F736974696F6E030B3Q0041696D417454617267657403113Q0063752Q72656E745461726765745061727403063Q00506172656E74030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73011F3Q0012E3000100016Q00028Q00010002000200122Q000200023Q00062Q0002001200013Q0004A13Q00120001001202000200033Q00062D0002001200013Q0004A13Q00120001001202000200033Q00203F01020002000400062D0002001200013Q0004A13Q00120001001202000200013Q001202000300034Q00930102000200020006332Q010012000100020004A13Q00120001001202000200054Q006E010300014Q00A50102000200030006130102001B000100010004A13Q001B0001001202000400064Q00A10104000100052Q006E010300054Q006E010200044Q006E010400024Q006E010500034Q008C000400034Q00D93Q00017Q00073Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403043Q004465616403053Q0056616C75652Q0103063Q004865616C7468028Q00011E3Q00202C2Q013Q000100124D010300024Q00A32Q01000300020006132Q010007000100010004A13Q000700012Q000D01026Q009D000200023Q00202C01020001000100124D010400034Q00A301020004000200062D0002001100013Q0004A13Q0011000100203F01030002000400262501030011000100050004A13Q001100012Q000D01036Q009D000300023Q00202C01030001000100124D010500064Q00A301030005000200062D0003001B00013Q0004A13Q001B000100203F0104000300040026170104001B000100070004A13Q001B00012Q000D01046Q009D000400024Q000D010400014Q009D000400024Q00D93Q00017Q00043Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403063Q004865616C746803053Q0056616C7565010F3Q00063D0001000500013Q0004A13Q0005000100202C2Q013Q000100124D010300024Q00A32Q010003000200063D0002000A000100010004A13Q000A000100202C01020001000100124D010400034Q00A301020004000200062D0002000E00013Q0004A13Q000E000100203F0103000200042Q009D000300024Q00D93Q00017Q00043Q00030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365029Q00074Q002B016Q00124Q00019Q003Q00124Q00023Q00124Q00043Q00124Q00038Q00017Q00083Q0003073Q00557365464B6579030B3Q006175746F46416374697665030D3Q006765744E6F64654865616C746803043Q007469636B030F3Q00737475636B4C6173744865616C746800030A3Q00737475636B53696E6365030F3Q00535455434B5F465F5345434F4E445301213Q001202000100013Q00062D0001000600013Q0004A13Q000600012Q000D2Q015Q001268000100024Q00D93Q00013Q001202000100034Q006E01026Q00932Q01000200020006132Q01000C000100010004A13Q000C00012Q00D93Q00013Q001202000200044Q0085000200010002001202000300053Q00261001030014000100060004A13Q00140001001202000300053Q0006D800010019000100030004A13Q00190001001268000100053Q001268000200074Q000D01035Q001268000300023Q0004A13Q00200001001202000300074Q0073010300020003001202000400083Q00062F00040020000100030004A13Q002000012Q000D010300013Q001268000300024Q00D93Q00017Q00083Q0003063Q00697061697273030B3Q004765744368696C6472656E03043Q004E616D6503063Q00486974626F782Q033Q0049734103083Q00426173655061727403053Q007461626C6503063Q00696E7365727401174Q00A900015Q00122Q000200013Q00202Q00033Q00024Q000300046Q00023Q000400044Q0013000100203F01070006000300262501070013000100040004A13Q0013000100202C01070006000500124D010900064Q00A301070009000200062D0007001300013Q0004A13Q00130001001202000700073Q00203F0107000700082Q006E010800014Q006E010900064Q00DF00070009000100065500020006000100020004A13Q000600012Q009D000100024Q00D93Q00017Q00033Q002Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C645768696368497341010C3Q00202C2Q013Q000100124D010300024Q00A32Q010003000200062D0001000600013Q0004A13Q000600012Q009D3Q00023Q00202C2Q013Q00030012BE000300026Q000400016Q000100046Q00019Q0000017Q00063Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403083Q00506F736974696F6E030B3Q00676574486974626F786573028Q00026Q00F03F01113Q00202C2Q013Q000100124D010300024Q00A32Q010003000200062D0001000700013Q0004A13Q0007000100203F0102000100032Q009D000200023Q001202000200044Q006E01036Q00930102000200022Q0068010300023Q000EDD00050010000100030004A13Q0010000100203F01030002000600203F0103000300032Q009D000300024Q00D93Q00017Q00073Q0003053Q007063612Q6C028Q00030F3Q00707573684661726D5761726E696E67030A3Q006E6F5F7461726765747303253Q00D09DD0B5D18220D186D0B5D0BBD0B5D0B920D0B4D0BBD18F20D0B4D0BED0B1D18BD187D0B803103Q00636C6561724661726D5761726E696E6703073Q006E6F5F6D6F6465001D4Q000B8Q000B00015Q001202000200013Q00064100033Q000100022Q006E017Q006E012Q00014Q003A0002000200012Q006801025Q000EDD0002000C000100020004A13Q000C00010006330102000D00013Q0004A13Q000D00012Q006E010200014Q0068010300023Q00262501030015000100020004A13Q00150001001202000300033Q00124D010400043Q00124D010500054Q00DF0003000500010004A13Q001B0001001202000300063Q001210000400046Q00030002000100122Q000300063Q00122Q000400076Q0003000200012Q009D000200024Q00D93Q00013Q00013Q00163Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030F3Q00707573684661726D5761726E696E67030F3Q006E6F5F696E746572616374696F6E7303203Q00D09DD0B5D18220496E746572616374696F6E7320D0B220776F726B737061636503103Q00636C6561724661726D5761726E696E6703053Q004E6F64657303083Q006E6F5F6E6F64657303173Q00D09DD0B5D18220D0BFD0B0D0BFD0BAD0B8204E6F64657303043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C69766503133Q0069734E6F6465496E426C6F636B65645A6F6E6503053Q007461626C6503063Q00696E7365727403043Q006E6F646503043Q006B696E6403043Q0074722Q6503093Q005265736F757263657303053Q0073746F6E6500563Q0012B83Q00013Q00206Q000200122Q000200038Q0002000200064Q000B000100010004A13Q000B0001001202000100043Q00124D010200053Q00124D010300064Q00DF0001000300012Q00D93Q00013Q001202000100073Q001230010200056Q00010002000100202Q00013Q000200122Q000300086Q00010003000200062Q00010018000100010004A13Q00180001001202000200043Q00124D010300093Q00124D0104000A4Q00DF0002000400012Q00D93Q00013Q001202000200073Q00124F000300096Q00020002000100202Q00020001000200122Q0004000B6Q00020004000200062Q0002003800013Q0004A13Q003800010012020003000C3Q00202C01040002000D2Q008F000400054Q00D200033Q00050004A13Q003600010012020008000E4Q006E010900074Q009301080002000200062D0008003600013Q0004A13Q003600010012020008000F4Q006E010900074Q009301080002000200061301080036000100010004A13Q00360001001202000800103Q00206E0008000800114Q00098Q000A3Q000200102Q000A0012000700302Q000A001300144Q0008000A000100065500030025000100020004A13Q0025000100202C01030001000200124D010500154Q00A301030005000200062D0003005500013Q0004A13Q005500010012020004000C3Q00202C01050003000D2Q008F000500064Q00D200043Q00060004A13Q005300010012020009000E4Q006E010A00084Q009301090002000200062D0009005300013Q0004A13Q005300010012020009000F4Q006E010A00084Q009301090002000200061301090053000100010004A13Q00530001001202000900103Q00206E0009000900114Q000A00016Q000B3Q000200102Q000B0012000800302Q000B001300164Q0009000B000100065500040042000100020004A13Q004200012Q00D93Q00017Q00043Q00028Q0003053Q007063612Q6C030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E74000D3Q00124D012Q00013Q00124D2Q0100013Q001202000200023Q00064100033Q000100022Q006E017Q006E012Q00014Q009201020002000100124Q00033Q00122Q000100046Q00028Q000300016Q000200038Q00013Q00013Q000A3Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E7303053Q004E6F64657303043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C697665026Q00F03F03093Q005265736F757263657300363Q0012B83Q00013Q00206Q000200122Q000200038Q0002000200064Q0007000100010004A13Q000700012Q00D93Q00013Q00202C2Q013Q000200124D010300044Q00A32Q01000300020006132Q01000D000100010004A13Q000D00012Q00D93Q00013Q00202C01020001000200124D010400054Q00A301020004000200062D0002002100013Q0004A13Q00210001001202000300063Q00202C0104000200072Q008F000400054Q00D200033Q00050004A13Q001F0001001202000800084Q006E010900074Q009301080002000200062D0008001F00013Q0004A13Q001F00012Q008100085Q0020950008000800092Q008001085Q00065500030017000100020004A13Q0017000100202C01030001000200124D0105000A4Q00A301030005000200062D0003003500013Q0004A13Q00350001001202000400063Q00202C0105000300072Q008F000500064Q00D200043Q00060004A13Q00330001001202000900084Q006E010A00084Q009301090002000200062D0009003300013Q0004A13Q003300012Q0081000900013Q0020950009000900092Q0080010900013Q0006550004002B000100020004A13Q002B00012Q00D93Q00017Q000C3Q00028Q00030E3Q00676574487562506F736974696F6E03063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403083Q00506F736974696F6E026Q00F03F03063Q00697061697273030D3Q006765744E6F646543656E74657203043Q006E6F646503093Q004D61676E697475646501324Q00682Q015Q0026252Q010005000100010004A13Q000500012Q0035000100014Q009D000100023Q001202000100024Q0085000100010002001202000200033Q00203F01020002000400062D0002001000013Q0004A13Q00100001001202000200033Q00203F01020002000400202C01020002000500124D010400064Q00A301020004000200062D0002001500013Q0004A13Q001500010006132Q010015000100010004A13Q0015000100203F2Q01000200070006132Q010019000100010004A13Q0019000100203F01033Q00082Q009D000300024Q0035000300043Q001202000500094Q006E01066Q00A50105000200070004A13Q002B0001001202000A000A3Q00203F010B0009000B2Q0093010A0002000200062D000A002B00013Q0004A13Q002B00012Q0073010B000A000100203F010B000B000C00062D0004002900013Q0004A13Q002900010006D8000B002B000100040004A13Q002B00012Q006E010300094Q006E0104000B3Q0006550005001E000100020004A13Q001E000100063301050030000100030004A13Q0030000100203F01053Q00082Q009D000500024Q00D93Q00017Q00043Q00030C3Q00706174726F6C506F696E747303053Q007063612Q6C030B3Q00706174726F6C496E646578026Q00F03F00084Q000B7Q0012683Q00013Q0012023Q00023Q00024700016Q003A3Q0002000100124D012Q00043Q0012683Q00034Q00D93Q00013Q00013Q00073Q0003063Q00697061697273030F3Q0067657456616C696454617267657473030D3Q006765744E6F646543656E74657203043Q006E6F646503053Q007461626C6503063Q00696E73657274030C3Q00706174726F6C506F696E747300123Q0012063Q00013Q00122Q000100026Q000100019Q00000200044Q000F0001001202000500033Q00203F0106000400042Q009301050002000200062D0005000F00013Q0004A13Q000F0001001202000600053Q00203F010600060006001202000700074Q006E010800054Q00DF0006000800010006553Q0005000100020004A13Q000500012Q00D93Q00017Q001A3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030C3Q00706174726F6C506F696E7473028Q00030B3Q00706174726F6C496E64657803073Q00566563746F72332Q033Q006E657703183Q0067657454656C65706F7274486569676874466F724B696E6403103Q006163746976655461726765744B696E64026Q00F03F030B3Q00736561726368416E676C65026Q66D63F030C3Q00736561726368526164697573026Q007940026Q005440026Q002E4003083Q00506F736974696F6E03043Q006D6174682Q033Q00636F732Q033Q0073696E03063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900573Q0012023Q00013Q00203F014Q000200062D3Q000900013Q0004A13Q000900010012023Q00013Q00203F014Q000200202C014Q000300124D010200044Q00A3012Q00020002000613012Q000C000100010004A13Q000C00012Q00D93Q00014Q0035000100013Q001202000200054Q0068010200023Q000EDD00060029000100020004A13Q00290001001202000200053Q001202000300074Q00C300020002000300062D0002001F00013Q0004A13Q001F0001001202000300083Q00200D00030003000900122Q000400063Q00122Q0005000A3Q00122Q0006000B6Q00050002000200122Q000600066Q0003000600024Q000100020003001202000300073Q00200401030003000C00122Q000300073Q00122Q000300073Q00122Q000400056Q000400043Q00062Q00040029000100030004A13Q0029000100124D0103000C3Q001268000300073Q0006132Q01004B000100010004A13Q004B00010012020002000D3Q00209500020002000E0012680002000D3Q0012020002000F3Q000EDD00100034000100020004A13Q0034000100124D010200113Q0012680002000F3Q0004A13Q003700010012020002000F3Q0020950002000200120012680002000F3Q00203F01023Q001300124B010300083Q00202Q00030003000900122Q000400143Q00202Q00040004001500122Q0005000D6Q00040002000200122Q0005000F6Q00040004000500122Q0005000A3Q00122Q0006000B6Q00050002000200122Q000600143Q00202Q00060006001600122Q0007000D6Q00060002000200122Q0007000F6Q0006000600074Q0003000600024Q000100020003001202000200173Q0020C90002000200094Q000300016Q00020002000200104Q0017000200122Q000200083Q00202Q00020002001900104Q0018000200122Q000200083Q00202Q00020002001900104Q001A00026Q00017Q00063Q002Q033Q0049734103053Q004D6F64656C03063Q0069706169727303103Q0044524F505F4D4F44454C5F48494E545303043Q004E616D6503043Q0066696E6401183Q00202C2Q013Q000100124D010300024Q00A32Q01000300020006132Q010007000100010004A13Q000700012Q000D2Q016Q009D000100023Q001202000100033Q001202000200044Q00A52Q01000200030004A13Q0013000100203F01063Q000500202C0106000600062Q006E010800054Q00A301060008000200062D0006001300013Q0004A13Q001300012Q000D010600014Q009D000600023Q0006550001000B000100020004A13Q000B00012Q000D2Q016Q009D000100024Q00D93Q00017Q00093Q0003103Q006163746976655461726765744B696E6403043Q004E616D6503043Q0066696E64030F3Q00436F2Q7065725265736F7572636573030D3Q004C6561665265736F757263657303053Q0073746F6E6503093Q00462Q6F644D6F64656C030D3Q00572Q6F645265736F757263657303043Q0074722Q6501203Q000613012Q0004000100010004A13Q00040001001202000100014Q009D000100023Q00203F2Q013Q000200202C01020001000300124D010400044Q00A30102000400020006130102000F000100010004A13Q000F000100202C01020001000300124D010400054Q00A301020004000200062D0002001100013Q0004A13Q0011000100124D010200064Q009D000200023Q00202C01020001000300124D010400074Q00A30102000400020006130102001B000100010004A13Q001B000100202C01020001000300124D010400084Q00A301020004000200062D0002001D00013Q0004A13Q001D000100124D010200094Q009D000200023Q001202000200014Q009D000200024Q00D93Q00017Q00023Q00030C3Q0069676E6F72656444726F707303063Q00506172656E7401133Q001202000100014Q00C3000100013Q00062D0001000600013Q0004A13Q000600012Q000D2Q0100014Q009D000100023Q00203F2Q013Q000200062D0001001000013Q0004A13Q00100001001202000100013Q00203F01023Q00022Q00C300010001000200062D0001001000013Q0004A13Q001000012Q000D2Q0100014Q009D000100024Q000D2Q016Q009D000100024Q00D93Q00017Q000B3Q00030C3Q0069676E6F72656444726F70732Q0103103Q006163746976655461726765744B696E6403063Q00506172656E742Q033Q0049734103053Q004D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C03053Q0073746F6E6503113Q0073652Q73696F6E53746F6E6544726F7073026Q00F03F03103Q0073652Q73696F6E54722Q6544726F7073011D3Q001279000100013Q00202Q00013Q000200122Q000100033Q00202Q00023Q000400062Q0002001300013Q0004A13Q0013000100203F01023Q000400202C01020002000500124D010400064Q00A301020004000200062D0002001300013Q0004A13Q00130001001202000200073Q00200001033Q00044Q0002000200024Q000100023Q00122Q000200013Q00202Q00033Q000400202Q0002000300020026252Q010019000100080004A13Q00190001001202000200093Q00209500020002000A001268000200093Q0004A13Q001C00010012020002000B3Q00209500020002000A0012680002000B4Q00D93Q00017Q00063Q0003063Q00506172656E74030D3Q00697344726F7049676E6F72656403123Q006973506F73496E426C6F636B65645A6F6E6503083Q00506F736974696F6E03013Q0059026Q00244002223Q00062D3Q000500013Q0004A13Q0005000100203F01023Q000100061301020007000100010004A13Q000700012Q000D01026Q009D000200023Q001202000200024Q006E01036Q009301020002000200062D0002000E00013Q0004A13Q000E00012Q000D01026Q009D000200023Q001202000200033Q00203F01033Q00042Q009301020002000200062D0002001500013Q0004A13Q001500012Q000D01026Q009D000200023Q00062D0001001F00013Q0004A13Q001F000100203F01023Q000400203F01020002000500203F0103000100052Q0073010200020003000EDD0006001F000100020004A13Q001F00012Q000D01026Q009D000200024Q000D010200014Q009D000200024Q00D93Q00017Q00183Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403063Q0043616D657261030F3Q00707573684661726D5761726E696E6703093Q006E6F5F63616D657261032A3Q00D09DD0B5D1822043616D65726120E2809420D0BBD183D18220D0BDD0B520D0BDD0B0D0B9D0B4D0B5D0BD03103Q00636C6561724661726D5761726E696E6703063Q00697061697273030B3Q004765744368696C6472656E03133Q0069735265736F7572636544726F704D6F64656C03063Q00506172656E74030E3Q00676574436F2Q6C6563745061727403123Q00697356616C6964436F2Q6C65637444726F7003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030E3Q00434F2Q4C4543545F52414449555303053Q007461626C6503063Q00696E7365727403043Q00736F727401464Q000B00015Q000613012Q0004000100010004A13Q000400012Q009D000100023Q001202000200013Q00202C01020002000200124D010400034Q00A30102000400020006130102000F000100010004A13Q000F0001001202000300043Q00124D010400053Q00124D010500064Q00DF0003000500012Q009D000100023Q001202000300073Q0012E7000400056Q00030002000100122Q000300083Q00202Q0004000200094Q000400056Q00033Q000500044Q003C00010012020008000A4Q006E010900074Q009301080002000200062D0008003C00013Q0004A13Q003C000100203F01080007000B00062D0008003C00013Q0004A13Q003C00010012020008000C4Q006E010900074Q009301080002000200062D0008003C00013Q0004A13Q003C00010012020009000D4Q006E010A00084Q006E010B6Q00A30109000B000200062D0009003C00013Q0004A13Q003C00010012020009000E3Q00205000090009000F00202Q000A0008001000202Q000A000A001100202Q000B3Q001200202Q000C0008001000202Q000C000C00134Q0009000C00024Q000900093Q00202Q00090009001400122Q000A00153Q00062Q0009003C0001000A0004A13Q003C0001001202000A00163Q00203F010A000A00172Q006E010B00014Q006E010C00084Q00DF000A000C000100065500030017000100020004A13Q00170001001202000300163Q00203F0103000300182Q006E010400013Q00064100053Q000100012Q006E017Q00DF0003000500012Q009D000100024Q00D93Q00013Q00013Q00073Q0003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465021E3Q00127A000200013Q00202Q00020002000200202Q00033Q000300202Q0003000300044Q00045Q00202Q00040004000500202Q00053Q000300202Q0005000500064Q0002000500024Q00038Q00020002000300202Q00020002000700122Q000300013Q00202Q00030003000200202Q00040001000300202Q0004000400044Q00055Q00202Q00050005000500202Q00060001000300202Q0006000600064Q0003000600024Q00048Q00030003000400202Q00030003000700062Q0002001B000100030004A13Q001B00012Q004000046Q000D010400014Q009D000400024Q00D93Q00017Q00023Q00030D3Q006765744E6F646543656E74657203173Q0066696E6443616D6572615265736F7572636544726F7073010C3Q001202000100014Q006E01026Q00932Q01000200020006132Q010007000100010004A13Q000700012Q000B00026Q009D000200023Q001202000200024Q006E010300014Q002E000200034Q003D01026Q00D93Q00017Q00073Q0003113Q006D61726B44726F70436F2Q6C656374656403163Q0046696E6446697273744368696C645768696368497341030F3Q0050726F78696D69747950726F6D707403063Q00506172656E7403053Q007063612Q6C030C3Q0073686F756C645072652Q734603063Q007072652Q734601223Q000613012Q0003000100010004A13Q000300012Q00D93Q00013Q001202000100014Q006401028Q00010002000100202Q00013Q000200122Q000300036Q000400016Q00010004000200062Q00010015000100010004A13Q0015000100203F01023Q000400062D0002001500013Q0004A13Q0015000100203F01023Q00040020CF00020002000200122Q000400036Q000500016Q0002000500024Q000100023Q00062D0001001B00013Q0004A13Q001B0001001202000200053Q00064100033Q000100012Q006E012Q00014Q003A000200020001001202000200064Q008500020001000200062D0002002100013Q0004A13Q00210001001202000200074Q00470102000100012Q00D93Q00013Q00013Q00013Q0003133Q006669726570726F78696D69747970726F6D707400043Q0012023Q00014Q008100016Q003A3Q000200012Q00D93Q00017Q00163Q0003093Q006661726D506861736503073Q00636F2Q6C656374030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E7454617267657450617274030D3Q006765744E6F646543656E746572030C3Q0069676E6F72656444726F7073026Q00F03F026Q00344003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E65617203063Q0069706169727303123Q00697356616C6964436F2Q6C65637444726F7003083Q00506F736974696F6E030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C6557616974027B14AE47E17AB43F030B3Q00636F2Q6C65637450617274029A5Q99A93F029A5Q99B93F03133Q0073746F704368617261637465724D6F74696F6E02593Q0012F7000200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200076Q00036Q00930102000200022Q009501035Q00122Q000300083Q00122Q000300093Q00122Q0004000A3Q00122Q000500093Q00042Q0003005400010012020007000B4Q006E010800014Q009301070002000200061301070017000100010004A13Q001700010004A13Q005400010012020007000C4Q006E01086Q00930107000200022Q0068010800073Q0026250108001E000100040004A13Q001E00010004A13Q005400010012020008000D4Q006E010900074Q00A501080002000A0004A13Q004A0001001202000D000B4Q006E010E00014Q0093010D00020002000613010D0028000100010004A13Q002800010004A13Q004A0001001202000D000E4Q006E010E000C4Q006E010F00024Q00A3010D000F0002000613010D002F000100010004A13Q002F00010004A13Q004A000100203F010D000C000F0012F3000E00106Q000F000D6Q000E0002000100122Q000C00063Q00122Q000E00113Q00122Q000F00126Q001000016Q000E0010000200062Q000E003B000100010004A13Q003B00010004A13Q004A0001001202000E00104Q006A000F000D6Q000E0002000100122Q000E00136Q000F000C6Q000E0002000100122Q000E00113Q00122Q000F00146Q001000016Q000E0010000200062Q000E0048000100010004A13Q004800010004A13Q004A00012Q0035000E000E3Q001268000E00063Q00065500080022000100020004A13Q00220001001202000800113Q00124D010900154Q006E010A00014Q00A30108000A000200061301080053000100010004A13Q005300010004A13Q005400010004030103001100012Q0035000300033Q001268000300063Q001202000300164Q00470103000100012Q00D93Q00017Q00053Q0003063Q007072652Q7346030F3Q0067657441696D5363722Q656E506F7303083Q00557365436C69636B03073Q00636C69636B4174030B3Q00686F6C644D6F7573654174011A3Q000613012Q0003000100010004A13Q000300012Q00D93Q00013Q001202000100014Q003F00010001000100122Q000100026Q00028Q00010002000200062Q0001000C00013Q0004A13Q000C00010006130102000D000100010004A13Q000D00012Q00D93Q00013Q001202000300033Q00062D0003001500013Q0004A13Q00150001001202000300044Q006E010400014Q006E010500024Q00DF0003000500010004A13Q00190001001202000300054Q006E010400014Q006E010500024Q00DF0003000500012Q00D93Q00017Q00043Q0003063Q0069706169727303163Q00412Q73656D626C794C696E65617256656C6F6369747903093Q004D61676E6974756465026Q00F83F010F3Q001202000100014Q006E01026Q00A52Q01000200030004A13Q000A000100203F01060005000200203F010600060003000EDD0004000A000100060004A13Q000A00012Q000D01066Q009D000600023Q00065500010004000100020004A13Q000400012Q000D2Q0100014Q009D000100024Q00D93Q00017Q000F3Q0003093Q006661726D506861736503043Q0077616974030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403113Q00696E74652Q7275707469626C6557616974026Q00D03F03043Q007469636B026Q00084003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E656172030F3Q0064726F707341726553652Q746C6564026Q00F03F029A5Q99B93F023E3Q00122D010200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200073Q00122Q000300084Q006E010400014Q00A301020004000200061301020010000100010004A13Q001000012Q000B00026Q009D000200023Q001202000200094Q008500020001000200209500020002000A0012020003000B4Q006E010400014Q009301030002000200062D0003003900013Q0004A13Q00390001001202000300094Q00850003000100020006D800030039000100020004A13Q003900010012020003000C4Q006E01046Q00930103000200022Q0068010400033Q000EDD00040029000100040004A13Q002900010012020004000D4Q006E010500034Q009301040002000200062D0004003000013Q0004A13Q003000012Q009D000300023Q0004A13Q00300001001202000400094Q008500040001000200205C01050002000E0006D800050030000100040004A13Q003000012Q000B00046Q009D000400023Q001202000400073Q00124D0105000F4Q006E010600014Q00A301040006000200061301040013000100010004A13Q001300012Q000B00046Q009D000400023Q0004A13Q001300010012020003000C4Q006E01046Q002E000300044Q003D01036Q00D93Q00017Q00023Q0003053Q0073746F6E65030D3Q006765744E6F646543656E746572030C3Q0026252Q01000A000100010004A13Q000A000100062D3Q000A00013Q0004A13Q000A0001001202000300024Q006E01046Q009301030002000200062D0003000A00013Q0004A13Q000A00012Q009D000300024Q009D000200024Q00D93Q00017Q00243Q0003093Q006661726D506861736503043Q006D696E6503113Q0063752Q72656E745461726765745061727403063Q00506172656E7403063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030F3Q0067657450617274506F736974696F6E03103Q006765744D696E65416E63686F72506F73030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403183Q0067657454656C65706F7274486569676874466F724B696E6403013Q0059030C3Q004F72626974456E61626C6564030A3Q006F72626974416E676C65030A3Q004F7262697453702Q6564026Q11913F030D3Q004F726269744469616D65746572027Q004003073Q00566563746F72332Q033Q006E657703013Q005803043Q006D6174682Q033Q00636F7303013Q005A2Q033Q0073696E030B3Q0041696D417454617267657403053Q0073746F6E6503063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747903083Q00557365436C69636B030F3Q0067657441696D5363722Q656E506F73030B3Q00686F6C644D6F757365417400743Q0012023Q00013Q002610012Q0004000100020004A13Q000400012Q00D93Q00013Q0012023Q00033Q00062D3Q000B00013Q0004A13Q000B00010012023Q00033Q00203F014Q0004000613012Q000C000100010004A13Q000C00012Q00D93Q00013Q0012023Q00053Q00203F014Q000600062D3Q001500013Q0004A13Q001500010012023Q00053Q00203F014Q000600202C014Q000700124D010200084Q00A3012Q00020002000613012Q0018000100010004A13Q001800012Q00D93Q00013Q001202000100093Q001202000200034Q00932Q01000200020006132Q01001E000100010004A13Q001E00012Q00D93Q00013Q0012020002000A3Q0012C80003000B3Q00122Q0004000C6Q000500016Q00020005000200122Q0003000D3Q00122Q0004000C6Q00030002000200202Q00040002000E4Q0004000400034Q000500053Q00122Q0006000F3Q00062Q0006004700013Q0004A13Q00470001001202000600103Q0012D7000700113Q00202Q0007000700124Q00060006000700122Q000600103Q00122Q000600133Q00202Q00060006001400122Q000700153Q00202Q00070007001600202Q00080002001700122Q000900183Q00202Q00090009001900122Q000A00106Q0009000200024Q0009000900064Q0008000800094Q000900043Q00202Q000A0002001A00122Q000B00183Q00202Q000B000B001B00122Q000C00106Q000B000200024Q000B000B00064Q000A000A000B4Q0007000A00024Q000500073Q00044Q004E0001001202000600153Q0020FC00060006001600202Q0007000200174Q000800043Q00202Q00090002001A4Q0006000900024Q000500063Q0012020006001C3Q00062D0006005B00013Q0004A13Q005B00010012020006000C3Q0026100106005B0001001D0004A13Q005B00010012020006001E3Q0020900006000600164Q000700056Q000800016Q00060008000200104Q001E000600044Q006000010012020006001E3Q00203F0106000600162Q006E010700054Q0093010600020002001099012Q001E0006001202000600153Q0020A500060006002000104Q001F000600122Q000600153Q00202Q00060006002000104Q0021000600122Q000600223Q00062Q00060073000100010004A13Q00730001001202000600033Q00062D0006007300013Q0004A13Q00730001001202000600233Q001270010700036Q00060002000700122Q000800246Q000900066Q000A00076Q0008000A00012Q00D93Q00017Q00023Q00030C3Q007363722Q656E477569526566030E3Q00497344657363656E64616E744F66010E3Q001202000100013Q00062D0001000C00013Q0004A13Q000C0001001202000100013Q0006183Q000B000100010004A13Q000B000100202C2Q013Q0002001202000300014Q00A32Q01000300020004A13Q000C00012Q004000016Q000D2Q0100014Q009D000100024Q00D93Q00017Q00073Q0003063Q00737472696E6703053Q006C6F77657203043Q004E616D6503063Q00697061697273030B3Q0054524144455F48494E545303043Q0066696E64026Q00F03F01183Q0012B0000100013Q00202Q00010001000200202Q00023Q00034Q00010002000200122Q000200043Q00122Q000300056Q00020002000400044Q00130001001202000700013Q0020960007000700064Q000800016Q000900063Q00122Q000A00076Q000B00016Q0007000B000200062Q0007001300013Q0004A13Q001300012Q000D010700014Q009D000700023Q00065500020008000100020004A13Q000800012Q000D01026Q009D000200024Q00D93Q00017Q00083Q0003083Q0069734F75724775692Q033Q0049734103093Q005363722Q656E47756903073Q00456E61626C6564010003093Q004775694F626A65637403073Q0056697369626C6503063Q0041637469766501153Q001202000100014Q006E01026Q00932Q010002000200062D0001000600013Q0004A13Q000600012Q00D93Q00013Q00202C2Q013Q000200124D010300034Q00A32Q010003000200062D0001000D00013Q0004A13Q000D0001003021012Q000400050004A13Q0014000100202C2Q013Q000200124D010300064Q00A32Q010003000200062D0001001400013Q0004A13Q00140001003021012Q00070005003021012Q000800052Q00D93Q00017Q00053Q00030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A65637403063Q00697061697273030E3Q0047657444657363656E64616E7473011E3Q001202000100013Q00062D0001000500013Q0004A13Q00050001000613012Q0006000100010004A13Q000600012Q00D93Q00013Q001202000100024Q006E01026Q00932Q010002000200062D0001000E00013Q0004A13Q000E0001001202000100034Q006E01026Q003A000100020001001202000100043Q00202C01023Q00052Q008F000200034Q00D200013Q00030004A13Q001B0001001202000600024Q006E010700054Q009301060002000200062D0006001B00013Q0004A13Q001B0001001202000600034Q006E010700054Q003A00060002000100065500010013000100020004A13Q001300012Q00D93Q00017Q000B3Q0003113Q00426C6F636B5569447572696E674661726D03063Q0069706169727303093Q00706C61796572477569030B3Q004765744368696C6472656E2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F757247756903073Q00456E61626C6564030A3Q0068692Q64656E477569733Q012Q001D3Q0012023Q00013Q000613012Q0004000100010004A13Q000400012Q00D93Q00013Q0012023Q00023Q001216000100033Q00202Q0001000100044Q000100029Q00000200044Q001A000100202C01050004000500124D010700064Q00A301050007000200062D0005001A00013Q0004A13Q001A0001001202000500074Q006E010600044Q00930105000200020006130105001A000100010004A13Q001A000100203F01050004000800062D0005001A00013Q0004A13Q001A0001001202000500093Q0020DA00050004000A00302101040008000B0006553Q000A000100020004A13Q000A00012Q00D93Q00017Q00023Q0003053Q0070616972730001083Q001202000100014Q006E01026Q00A52Q01000200030004A13Q000500010020DA3Q0004000200065500010004000100010004A13Q000400012Q00D93Q00017Q000A3Q0003053Q00706169727303133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q007063612Q6C030A3Q00636C6561725461626C65030A3Q0068692Q64656E4775697303063Q00506172656E742Q0103043Q006E65787403043Q007461736B03053Q006465666572002B3Q0012023Q00013Q001202000100024Q00A5012Q000200020004A13Q000B000100062D0004000A00013Q0004A13Q000A0001001202000500033Q00064100063Q000100012Q006E012Q00044Q003A0005000200012Q00D600035Q0006553Q0004000100020004A13Q000400010012023Q00043Q00122A2Q0100028Q000200019Q0000122Q000100013Q00122Q000200056Q00010002000300044Q001B000100203F01060004000600062D0006001B00013Q0004A13Q001B000100062D0005001B00013Q0004A13Q001B00010020DA3Q0004000700065500010015000100020004A13Q00150001001202000100043Q001248010200056Q00010002000100122Q000100086Q00028Q00010002000200062Q0001002A00013Q0004A13Q002A0001001202000100093Q00203F2Q010001000A00064100020001000100012Q006E017Q003A0001000200012Q00D93Q00013Q00023Q00013Q00030A3Q00446973636F2Q6E65637400044Q00817Q00202C014Q00012Q003A3Q000200012Q00D93Q00017Q00043Q0003053Q00706169727303063Q00506172656E7403073Q00456E61626C65642Q01000B3Q0012023Q00014Q008100016Q00A5012Q000200020004A13Q0008000100203F01040003000200062D0004000800013Q0004A13Q000800010030210103000300040006553Q0004000100010004A13Q000400012Q00D93Q00017Q000A3Q00030C3Q0073746F70536166654D6F6465030D3Q00686964654F7468657247756973030A3Q007363616E54726164657303093Q00706C6179657247756903133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q006368696C64030A3Q004368696C64412Q64656403073Q00436F2Q6E65637403043Q0064657363030F3Q0044657363656E64616E74412Q64656400163Q00129C012Q00018Q0001000100124Q00028Q0001000100124Q00033Q00122Q000100048Q0002000100124Q00053Q00122Q000100043Q00202Q00010001000700202C2Q010001000800024700036Q000800010003000200104Q0006000100124Q00053Q00122Q000100043Q00202Q00010001000A00202Q000100010008000247000300014Q00A32Q0100030002001099012Q000900012Q00D93Q00013Q00023Q00033Q00030B3Q004661726D456E61626C656403043Q007461736B03053Q006465666572010A3Q001202000100013Q0006132Q010004000100010004A13Q000400012Q00D93Q00013Q001202000100023Q00203F2Q010001000300064100023Q000100012Q006E017Q003A0001000200012Q00D93Q00013Q00013Q00093Q0003113Q00426C6F636B5569447572696E674661726D2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F7572477569030A3Q0068692Q64656E477569732Q0103073Q00456E61626C65640100030A3Q007363616E54726164657300173Q0012023Q00013Q00062D3Q001300013Q0004A13Q001300012Q00817Q00202C014Q000200124D010200034Q00A3012Q0002000200062D3Q001300013Q0004A13Q001300010012023Q00044Q008100016Q0093012Q00020002000613012Q0013000100010004A13Q001300010012023Q00054Q008100015Q0020DA3Q000100062Q00817Q003021012Q000700080012023Q00094Q008100016Q003A3Q000200012Q00D93Q00017Q00053Q00030B3Q004661726D456E61626C6564030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B65547261646503043Q007461736B03053Q00646566657201123Q001202000100013Q00062D0001000600013Q0004A13Q00060001001202000100023Q0006132Q010007000100010004A13Q000700012Q00D93Q00013Q001202000100034Q006E01026Q00932Q010002000200062D0001001100013Q0004A13Q00110001001202000100043Q00203F2Q010001000500064100023Q000100012Q006E017Q003A0001000200012Q00D93Q00013Q00013Q00013Q00030F3Q006869646554726164654F626A65637400043Q0012023Q00014Q008100016Q003A3Q000200012Q00D93Q00017Q00043Q0003063Q00706C61796572030E3Q0046696E6446697273744368696C6403043Q004461746103093Q005265736F7572636573000D3Q0012B83Q00013Q00206Q000200122Q000200038Q0002000200064Q0008000100010004A13Q000800012Q0035000100014Q009D000100023Q00202C2Q013Q000200124D010300044Q002E000100034Q003D2Q016Q00D93Q00017Q00073Q0003123Q006765745265736F7572636573466F6C646572028Q00030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565011A3Q001202000100014Q00850001000100020006132Q010006000100010004A13Q0006000100124D010200024Q009D000200023Q00202C0102000100032Q006E01046Q00A301020004000200062D0002001700013Q0004A13Q0017000100202C01030002000400124D010500054Q00A301030005000200061301030015000100010004A13Q0015000100202C01030002000400124D010500064Q00A301030005000200062D0003001700013Q0004A13Q0017000100203F0103000200072Q009D000300023Q00124D010300024Q009D000300024Q00D93Q00017Q00053Q00028Q0003073Q00436F636F6E757403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7400133Q00126B012Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300046Q00020002000400044Q000D0001001202000700054Q006E010800064Q00930107000200020006D83Q000D000100070004A13Q000D00012Q006E012Q00074Q006E2Q0100063Q00065500020006000100020004A13Q000600012Q006E01026Q006E010300014Q008C000200034Q00D93Q00017Q00053Q00030F3Q004175746F53652Q6C456E61626C656403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7403143Q0053652Q6C436F636F6E75745468726573686F6C6400163Q0012023Q00013Q000613012Q0005000100010004A13Q000500012Q000D017Q009D3Q00023Q0012023Q00023Q001202000100034Q00A5012Q000200020004A13Q00110001001202000500044Q006E010600044Q0093010500020002001202000600053Q0006D800060011000100050004A13Q001100012Q000D010500014Q009D000500023Q0006553Q0009000100020004A13Q000900012Q000D017Q009D3Q00024Q00D93Q00017Q00073Q00030D3Q006661726D54696D65546F74616C030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q0003043Q007469636B03043Q006D61746803053Q00666C2Q6F7200123Q0012023Q00013Q001202000100023Q00062D0001000C00013Q0004A13Q000C0001001202000100033Q000EDD0004000C000100010004A13Q000C0001001202000100054Q0085000100010002001202000200034Q00732Q01000100022Q007C014Q0001001202000100063Q0020452Q01000100074Q00028Q000100026Q00019Q0000017Q00073Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E2Q033Q0073796E03043Q00682Q7470030B3Q00482Q747053657276696365030C3Q00526571756573744173796E63013A3Q00024700015Q001202000200013Q001202000300024Q00930102000200020026250102000D000100030004A13Q000D00012Q006E010200013Q00064100030001000100012Q006E017Q009301020002000200062D0002000D00013Q0004A13Q000D00012Q009D000200023Q001202000200043Q00062D0002001B00013Q0004A13Q001B0001001202000200043Q00203F01020002000200062D0002001B00013Q0004A13Q001B00012Q006E010200013Q00064100030002000100012Q006E017Q009301020002000200062D0002001B00013Q0004A13Q001B00012Q009D000200023Q001202000200053Q00062D0002002900013Q0004A13Q00290001001202000200053Q00203F01020002000200062D0002002900013Q0004A13Q002900012Q006E010200013Q00064100030003000100012Q006E017Q009301020002000200062D0002002900013Q0004A13Q002900012Q009D000200023Q001202000200063Q00062D0002003700013Q0004A13Q00370001001202000200063Q00203F01020002000700062D0002003700013Q0004A13Q003700012Q006E010200013Q00064100030004000100012Q006E017Q009301020002000200062D0002003700013Q0004A13Q003700012Q009D000200024Q0035000200024Q009D000200024Q00D93Q00013Q00053Q00013Q0003053Q007063612Q6C01093Q001202000100014Q006E01026Q00A52Q010002000200062D0001000600013Q0004A13Q000600012Q009D000200024Q0035000300034Q009D000300024Q00D93Q00017Q00013Q0003073Q007265717565737400053Q0012573Q00016Q00019Q0000019Q008Q00017Q00023Q002Q033Q0073796E03073Q007265717565737400063Q00122B3Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00023Q0003043Q00682Q747003073Q007265717565737400063Q00122B3Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00073Q00030B3Q00482Q747053657276696365030C3Q00526571756573744173796E632Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q004865616465727303043Q00426F647900153Q001259012Q00013Q00206Q00024Q00023Q00044Q00035Q00202Q00030003000300102Q0002000300034Q00035Q00202Q00030003000400062Q0003000B000100010004A13Q000B000100124D010300053Q0010990102000400032Q005E01035Q00202Q00030003000600102Q0002000600034Q00035Q00202Q00030003000700102Q0002000700036Q00029Q008Q00017Q001F3Q0003043Q006773756203043Q005E25732B034Q0003043Q0025732B2403143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B9030B3Q00682Q7470526571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030A3Q00537461747573436F646503063Q0073746174757303063Q0053746174757303083Q00746F6E756D626572026Q006940025Q00C0724003143Q00D09ED182D0BFD180D0B0D0B2D0BBD0B5D0BDD0BE03053Q00482Q54502003083Q00746F737472696E6703073Q0053752Q63652Q733Q010003113Q00482Q545020D0BED188D0B8D0B1D0BAD0B003053Q007063612Q6C031D3Q00D09ED188D0B8D0B1D0BAD0B020D0BED182D0BFD180D0B0D0B2D0BAD0B82Q033Q00737562026Q00F03F026Q005840025D3Q00208801023Q000100122Q000400023Q00122Q000500036Q00020005000200202Q00020002000100122Q000400043Q00122Q000500036Q0002000500026Q00023Q00264Q000E000100030004A13Q000E00012Q000D01025Q00124D010300054Q008C000200033Q001202000200064Q000201033Q000400102Q000300073Q00302Q0003000800094Q00043Q000100302Q0004000B000C00102Q0003000A000400102Q0003000D00014Q00020002000200062Q0002004700013Q0004A13Q0047000100203F01030002000E00061301030020000100010004A13Q0020000100203F01030002000F00061301030020000100010004A13Q0020000100203F01030002001000062D0003003800013Q0004A13Q00380001001202000400114Q006E010500034Q009301040002000200062D0004003800013Q0004A13Q00380001001202000400114Q006E010500034Q0093010400020002000E6400120031000100040004A13Q0031000100263A01040031000100130004A13Q003100012Q000D010500013Q00124D010600144Q008C000500034Q000D01055Q001222010600153Q00122Q000700166Q000800036Q0007000200024Q0006000600074Q000500033Q00203F0104000200170026250104003E000100180004A13Q003E00012Q000D010400013Q00124D010500144Q008C000400033Q00203F01040002001700262501040044000100190004A13Q004400012Q000D01045Q00124D0105001A4Q008C000400034Q000D010400013Q00124D010500144Q008C000400033Q0012020003001B3Q00064100043Q000100022Q006E017Q006E012Q00014Q00A501030002000400062D0003005100013Q0004A13Q005100012Q000D010500013Q00124D010600144Q008C000500034Q000D01055Q001202000600163Q00063301070056000100040004A13Q0056000100124D0107001C4Q00930106000200020020BF00060006001D00122Q0008001E3Q00122Q0009001F6Q000600096Q00059Q0000013Q00013Q00053Q00030B3Q00482Q74705365727669636503093Q00506F73744173796E6303043Q00456E756D030F3Q00482Q7470436F6E74656E7454797065030F3Q00412Q706C69636174696F6E4A736F6E000A3Q001215012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400033Q00202Q00040004000400202Q0004000400054Q00059Q00000500016Q00017Q001F3Q00034Q0003143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B903043Q006E616D65030A3Q00D098D0B3D180D0BED0BA03053Q0076616C756503063Q00706C6179657203043Q004E616D652Q033Q0020286003083Q00746F737472696E6703063Q0055736572496403023Q00602903063Q00696E6C696E65010003063Q0069706169727303053Q007461626C6503063Q00696E73657274030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646503063Q00656D6265647303053Q007469746C6503053Q00636F6C6F72023Q00806D4C4A4103063Q006669656C647303063Q00662Q6F74657203043Q007465787403083Q004D4158492048554203093Q0074696D657374616D7003083Q004461746554696D652Q033Q006E6F7703093Q00546F49736F4461746503123Q00706F7374446973636F7264576562682Q6F6B04403Q00062D3Q000400013Q0004A13Q00040001002625012Q0007000100010004A13Q000700012Q000D01045Q00124D010500024Q008C000400034Q000B000400014Q008501053Q000300302Q00050003000400122Q000600063Q00202Q00060006000700122Q000700083Q00122Q000800093Q00122Q000900063Q00202Q00090009000A4Q00080002000200122Q0009000B6Q00060006000900102Q00050005000600302Q0005000C000D4Q00040001000100062D0003002300013Q0004A13Q002300010012020005000E4Q006E010600034Q00A50105000200070004A13Q00210001001202000A000F3Q00203F010A000A00102Q006E010B00044Q006E010C00094Q00DF000A000C00010006550005001C000100020004A13Q001C0001001202000500113Q0020780105000500124Q00073Q00014Q000800016Q00093Q000500102Q00090014000100062Q000A002C000100020004A13Q002C000100124D010A00163Q00109901090015000A00107E0109001700044Q000A3Q000100302Q000A0019001A00102Q00090018000A00122Q000A001C3Q00202Q000A000A001D4Q000A0001000200202Q000A000A001E4Q000A0002000200102Q0009001B000A4Q0008000100010010990107001300082Q009801050007000200122Q0006001F6Q00078Q000800056Q000600086Q00069Q0000017Q00193Q0003123Q006765745265736F7572636573466F6C6465722Q033Q00E2809403063Q00697061697273030B3Q004765744368696C6472656E2Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565026Q00F03F03053Q007461626C6503063Q00696E7365727403043Q006E616D6503043Q004E616D652Q033Q0076616C03043Q00736F727403023Q003A2003083Q00746F737472696E6703063Q00636F6E63617403013Q000A025Q00408F4003063Q00737472696E672Q033Q00737562025Q00288F402Q033Q003Q2E029Q00523Q0012023Q00014Q00853Q00010002000613012Q0006000100010004A13Q0006000100124D2Q0100024Q009D000100024Q000B00015Q001216000200033Q00202Q00033Q00044Q000300046Q00023Q000400044Q0022000100202C01070006000500124D010900064Q00A301070009000200061301070016000100010004A13Q0016000100202C01070006000500124D010900074Q00A301070009000200062D0007002200013Q0004A13Q0022000100203F010700060008000EDD00090022000100070004A13Q002200010012020007000A3Q0020DC00070007000B4Q000800016Q00093Q000200202Q000A0006000D00102Q0009000C000A00202Q000A0006000800102Q0009000E000A4Q0007000900010006550002000C000100020004A13Q000C00010012020002000A3Q00203F01020002000F2Q006E010300013Q00024700046Q00C10002000400014Q00025Q00122Q000300036Q000400016Q00030002000500044Q003800010012020008000A3Q00202500080008000B4Q000900023Q00202Q000A0007000C00122Q000B00103Q00122Q000C00113Q00202Q000D0007000E4Q000C000200024Q000A000A000C4Q0008000A00010006550003002E000100020004A13Q002E00010012020003000A3Q0020890103000300124Q000400023Q00122Q000500136Q0003000500024Q000400033Q000E2Q0014004A000100040004A13Q004A0001001202000400153Q00203B0004000400164Q000500033Q00122Q000600093Q00122Q000700176Q00040007000200122Q000500186Q0003000400052Q0068010400023Q000EDD0019004F000100040004A13Q004F000100063301040050000100030004A13Q0050000100124D010400024Q009D000400024Q00D93Q00013Q00013Q00013Q002Q033Q0076616C02083Q00203F01023Q000100203F01030001000100066000030005000100020004A13Q000500012Q004000026Q000D010200014Q009D000200024Q00D93Q00017Q001C3Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D617403093Q002564D0BC202564D18103023Q00D18103043Q006E616D65031D3Q00D0A1D180D183D0B1D0B8D0BB20D0B4D0B5D180D0B5D0B2D18CD0B5D0B203053Q0076616C756503083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q00696E6C696E652Q0103193Q00D0A1D180D183D0B1D0B8D0BB20D0BAD0B0D0BCD0BDD0B5D0B903123Q0073652Q73696F6E53746F6E65734D696E6564031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0B4D0B5D1802E2903103Q0073652Q73696F6E54722Q6544726F7073031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0BAD0B0D0BC2E2903113Q0073652Q73696F6E53746F6E6544726F707303153Q00D092D180D0B5D0BCD18F20D184D0B0D180D0BCD0B0030A3Q00D0A0D0B5D0B6D0B8D0BC030F3Q006765744661726D4D6F646554657874030E3Q005265736F757263657320283E312903173Q006765745265736F75726365734F7665724F6E6554657874012Q00453Q001227012Q00018Q0001000200122Q000100023Q00202Q00010001000300202Q00023Q00044Q00010002000200202Q00023Q00044Q000300033Q000E2Q00050012000100010004A13Q00120001001202000400063Q0020F400040004000700122Q000500086Q000600016Q000700026Q0004000700024Q000300043Q00044Q001500012Q006E01045Q00124D010500094Q00600103000400052Q000B000400074Q007D00053Q000300302Q0005000A000B00122Q0006000D3Q00122Q0007000E6Q00060002000200102Q0005000C000600302Q0005000F00104Q00063Q000300302Q0006000A001100122Q0007000D3Q00122Q000800126Q00070002000200102Q0006000C000700302Q0006000F00104Q00073Q000300302Q0007000A001300122Q0008000D3Q00122Q000900146Q00080002000200102Q0007000C000800302Q0007000F00104Q00083Q000300302Q0008000A001500122Q0009000D3Q00122Q000A00166Q00090002000200102Q0008000C000900302Q0008000F00104Q00093Q000300302Q0009000A001700102Q0009000C000300302Q0009000F00104Q000A3Q000300302Q000A000A001800122Q000B00196Q000B0001000200102Q000A000C000B00302Q000A000F00104Q000B3Q000300302Q000B000A001A00122Q000C001B6Q000C0001000200102Q000B000C000C00302Q000B000F001C4Q0004000700012Q009D000400024Q00D93Q00017Q00083Q0003153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003063Q0069706169727303153Q0067657453652Q73696F6E53746174734669656C647303053Q007461626C6503063Q00696E7365727403103Q0073656E64446973636F7264456D626564021F3Q001202000200013Q00061301020004000100010004A13Q000400012Q00D93Q00013Q001202000200024Q008500020001000200062D0002000A00013Q0004A13Q000A00010026250102000B000100030004A13Q000B00012Q00D93Q00014Q000B00035Q001206000400043Q00122Q000500056Q000500016Q00043Q000600044Q00160001001202000900063Q00203F0109000900072Q006E010A00034Q006E010B00084Q00DF0009000B000100065500040011000100020004A13Q00110001001202000400084Q00E6000500026Q00068Q000700016Q000800036Q0004000800016Q00017Q00093Q0003043Q007469636B026Q00284003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403043Q007461736B03043Q0077616974029A5Q99B93F011C3Q001202000100014Q00850001000100020006330102000500013Q0004A13Q0005000100124D010200024Q007C2Q0100010002001202000200014Q00850002000100020006D800020019000100010004A13Q00190001001202000200033Q00203F01020002000400063D00030011000100020004A13Q0011000100202C01030002000500124D010500064Q00A301030005000200062D0003001400013Q0004A13Q001400012Q009D000300023Q001202000400073Q00203F01040004000800124D010500094Q003A0004000200010004A13Q000600012Q0035000200024Q009D000200024Q00D93Q00017Q00053Q0003053Q00666F72636503043Q007461736B03043Q007761697403113Q00696E74652Q7275707469626C655761697403053Q0072756E496402133Q00062D0001000B00013Q0004A13Q000B000100203F01020001000100062D0002000B00013Q0004A13Q000B0001001202000200023Q0020C40002000200034Q00038Q0002000200014Q000200016Q000200023Q001202000200044Q006E01035Q00063D00040010000100010004A13Q0010000100203F0104000100052Q002E000200044Q003D01026Q00D93Q00017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E40030E3Q0053652Q6C4974656D52656D6F7465000F3Q001206012Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q0009000100010004A13Q000900012Q0035000100014Q009D000100023Q00202C2Q013Q0002001258010300053Q00122Q000400046Q000100046Q00019Q0000017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E4003133Q00576F726C6454656C65706F727452656D6F7465000F3Q001206012Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q0009000100010004A13Q000900012Q0035000100014Q009D000100023Q00202C2Q013Q0002001258010300053Q00122Q000400046Q000100046Q00019Q0000017Q00023Q0003163Q00676574576F726C6454656C65706F727452656D6F746503053Q007063612Q6C010D3Q001202000100014Q00850001000100020006132Q010006000100010004A13Q000600012Q000D01026Q009D000200023Q001202000200023Q00064100033Q000100022Q006E017Q006E012Q00014Q00930102000200022Q009D000200024Q00D93Q00013Q00013Q00053Q00026Q00F03F027Q0040030C3Q00496E766F6B6553657276657203053Q007461626C6503063Q00756E7061636B000D4Q00FD5Q00024Q00015Q00104Q000100014Q00015Q00104Q000200014Q000100013Q00202Q00010001000300122Q000300043Q00202Q0003000300054Q00046Q008F000300044Q002700013Q00012Q00D93Q00017Q00023Q00030D3Q0067657453652Q6C52656D6F746503053Q007063612Q6C010D3Q001202000100014Q00850001000100020006132Q010006000100010004A13Q000600012Q000D01026Q009D000200023Q001202000200023Q00064100033Q000100022Q006E017Q006E012Q00014Q00930102000200022Q009D000200024Q00D93Q00013Q00013Q00073Q00026Q00F03F03083Q004974656D4E616D6503063Q00416D6F756E74030F3Q0053652Q6C4261746368416D6F756E74030A3Q004669726553657276657203053Q007461626C6503063Q00756E7061636B000F4Q00BA5Q00014Q00013Q00024Q00025Q00102Q00010002000200122Q000200043Q00102Q00010003000200104Q000100014Q000100013Q00202Q00010001000500122Q000300063Q00202Q0003000300074Q00048Q000300046Q00013Q00016Q00017Q002C3Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003053Q00666F726365030F3Q004175746F53652Q6C456E61626C6564030D3Q006E2Q6564734175746F53652Q6C03093Q006661726D506861736503043Q0073652Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03103Q00636C6561724661726D5761726E696E6703093Q0073652Q6C5F6661696C030D3Q007361766553652Q6C537461746503063Q006D616E75616C2Q01030A3Q00726573756D654661726D031B3Q00D0A2D09F20D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D1833Q2E030D3Q00776F726C6454656C65706F7274030D3Q0053452Q4C5F574F524C445F4944030E3Q00636C65617253652Q6C5374617465030F3Q00707573684661726D5761726E696E6703383Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D182D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18303043Q0069646C6503363Q00D0A2D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18320D0BDD0B520D183D0B4D0B0D0BBD181D18F03253Q00D096D0B4D191D0BC20D0B7D0B0D0B3D180D183D0B7D0BAD18320D0BCD0B8D180D0B03Q2E03133Q0077616974466F72436861726163746572487270026Q00284003123Q0053452Q4C5F574149545F41465445525F5450031F3Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0B5D180D0B2D0B0D0BDD0B0030D3Q006C6F616453652Q6C537461746503053Q00706861736503493Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0BED0B4D0BED0BBD0B6D0B8D182D181D18F20D0BFD0BED181D0BBD0B520D0BFD0B5D180D0B5D0B7D0B0D0B3D180D183D0B7D0BAD0B803203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D7303233Q0053652Q6C4974656D52656D6F746520D0BDD0B5D0B4D0BED181D182D183D0BFD0B5D0BD026Q00F03F03063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q004641524D5F574F524C445F494403343Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0B2D0B5D180D0BDD183D182D18CD181D18F20D0BDD0B020D184D0B0D180D0BC027Q004003123Q0066696E616C697A6553652Q6C526573756D6503323Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD180D0BED0B4D0B0D182D18C2028D0BDD0B5D1822072656D6F74652903213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B002CC3Q0006132Q010004000100010004A13Q000400012Q000B00026Q006E2Q0100023Q001202000200013Q00062D0002000A00013Q0004A13Q000A00012Q000D01025Q00124D010300024Q008C000200033Q00203F01020001000300061301020018000100010004A13Q00180001001202000200043Q00061301020012000100010004A13Q001200012Q000D01026Q009D000200023Q001202000200054Q008500020001000200061301020018000100010004A13Q001800012Q000D01026Q009D000200023Q00064100023Q000100012Q006E012Q00013Q00064100030001000100022Q006E012Q00014Q006E016Q00064100040002000100022Q006E012Q00014Q006E017Q002E010500013Q00122Q000500013Q00122Q000500073Q00122Q000500063Q00122Q000500086Q00050001000100122Q000500096Q00050001000100122Q0005000A6Q00050001000100122Q0005000B3Q00122Q0006000C6Q00050002000100122Q0005000D3Q00122Q000600076Q00073Q000200202Q00080001000300262Q000800340001000F0004A13Q003400012Q004000086Q000D010800013Q0010990107000E000800203F0108000100100026100108003A0001000F0004A13Q003A00012Q004000086Q000D010800013Q00106F0107001000084Q0005000700014Q000500023Q00122Q000600116Q00050002000100122Q000500123Q00122Q000600136Q00050002000200062Q00050052000100010004A13Q00520001001202000500144Q00DB00050001000100122Q000500153Q00122Q0006000C3Q00122Q000700166Q0005000700014Q00055Q00122Q000500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q000600186Q000500034Q006E010500023Q001251010600196Q00050002000100122Q0005001A3Q00122Q0006001B6Q0005000200014Q000500033Q00122Q0006001C6Q00050002000200062Q00050066000100010004A13Q00660001001202000500144Q00D30005000100014Q00055Q00122Q000500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q0006001D6Q000500033Q0012020005001E4Q008500050001000200062D0005006D00013Q0004A13Q006D000100203F01060005001F00261001060074000100070004A13Q007400012Q000D01065Q001253000600013Q00122Q000600173Q00122Q000600066Q000600013Q00122Q000700206Q000600034Q006E010600023Q00123E010700216Q00060002000100122Q000600226Q000700036Q000800046Q00060008000200062Q00060081000100010004A13Q00810001001202000700153Q00124D0108000C3Q00124D010900234Q00DF0007000900012Q006E010700033Q00124D010800244Q00930107000200020006130107008F000100010004A13Q008F0001001202000700144Q00D30007000100014Q00075Q00122Q000700013Q00122Q000700173Q00122Q000700066Q00075Q00122Q0008001D6Q000700033Q0012020007000D3Q00124D010800254Q000B00093Q000200203F010A00010003002610010A00960001000F0004A13Q009600012Q0040000A6Q000D010A00013Q0010990109000E000A00203F010A00010010002610010A009C0001000F0004A13Q009C00012Q0040000A6Q000D010A00013Q00106F01090010000A4Q0007000900014Q000700023Q00122Q000800266Q00070002000100122Q000700123Q00122Q000800276Q00070002000200062Q000700AB000100010004A13Q00AB0001001202000700153Q00124D0108000C3Q00124D010900284Q00DF0007000900010012020007001A3Q0012390008001B6Q0007000200014Q000700033Q00122Q000800296Q00070002000100122Q0007001E6Q00070001000200062Q000700BC00013Q0004A13Q00BC000100203F01080007001F002625010800BC000100250004A13Q00BC00010012020008002A4Q006E010900014Q006E010A00064Q00DF0008000A00012Q000D01085Q0012B5000800013Q00122Q000800173Q00122Q000800063Q00122Q0008000B3Q00122Q0009000C6Q00080002000100062Q000600C8000100010004A13Q00C800012Q000D01085Q00124D0109002B4Q008C000800034Q000D010800013Q00124D0109002C4Q008C000800034Q00D93Q00013Q00033Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q008100015Q00203F2Q010001000100062D0001000900013Q0004A13Q00090001001202000100024Q008100025Q00203F0102000200012Q006E01036Q00DF0001000300012Q00D93Q00017Q00033Q0003083Q0073652Q6C5761697403053Q00666F72636503053Q0072756E4964010B3Q001231000100016Q00028Q00033Q00024Q00045Q00202Q00040004000200102Q0003000200044Q000400013Q00102Q0003000300044Q000100036Q00016Q00D93Q00017Q00033Q0003053Q00666F726365030E3Q0073652Q6C496E50726F6772652Q7303123Q0073686F756C644661726D436F6E74696E7565000B4Q00817Q00203F014Q000100062D3Q000600013Q0004A13Q000600010012023Q00024Q009D3Q00023Q0012023Q00034Q0081000100014Q002E3Q00014Q003D017Q00D93Q00017Q00053Q00030C3Q0072756E53652Q6C4379636C6503053Q00666F7263650100030A3Q00726573756D654661726D3Q01073Q0012F2000100016Q00028Q00033Q000200302Q00030002000300302Q0003000400054Q0001000300016Q00017Q00043Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003043Q007461736B03053Q00737061776E01103Q001202000100013Q00062D0001000A00013Q0004A13Q000A000100062D3Q000900013Q0004A13Q000900012Q006E2Q016Q000D01025Q00124D010300024Q00DF0001000300012Q00D93Q00013Q001202000100033Q00203F2Q010001000400064100023Q000100012Q006E017Q003A0001000200012Q00D93Q00013Q00013Q000F3Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964026Q00F03F030E3Q006661726D436865636B506175736503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030C3Q0072756E53652Q6C4379636C6503053Q00666F7263652Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303133Q0068617350656E64696E6753652Q6C537461746503093Q0073746172744661726D002E3Q0012023Q00013Q00062D3Q000600013Q0004A13Q00060001001202000100023Q002095000100010003001268000100024Q000D2Q0100013Q0012A6000100043Q00122Q000100053Q00122Q000200066Q00010002000100122Q000100053Q00122Q000200076Q00010002000100122Q000100053Q00122Q000200086Q000100020001001202000100094Q0035000200024Q000B00033Q00030030210103000A000B0010990103000C3Q00024700045Q0010610003000D00044Q0001000300024Q00035Q00122Q000300043Q00064Q002600013Q0004A13Q00260001001202000300013Q00062D0003002600013Q0004A13Q002600010012020003000E4Q008500030001000200061301030026000100010004A13Q002600010012020003000F4Q00470103000100012Q008100035Q00062D0003002D00013Q0004A13Q002D00012Q008100036Q006E010400014Q006E010500024Q00DF0003000500012Q00D93Q00013Q00013Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q001202000100013Q00062D0001000900013Q0004A13Q00090001001202000100013Q00203F2Q010001000200062D0001000900013Q0004A13Q00090001001202000100013Q0010992Q0100034Q00D93Q00017Q00073Q00030F3Q004175746F53652Q6C456E61626C6564030E3Q0073652Q6C496E50726F6772652Q7303043Q007469636B030F3Q006C61737453652Q6C436865636B417403113Q0053652Q6C436865636B496E74657276616C030D3Q006E2Q6564734175746F53652Q6C030B3Q0072756E4175746F53652Q6C01183Q001202000100013Q00062D0001000600013Q0004A13Q00060001001202000100023Q00062D0001000700013Q0004A13Q000700012Q00D93Q00013Q001202000100034Q008300010001000200122Q000200046Q00020001000200122Q000300053Q00062Q0002000F000100030004A13Q000F00012Q00D93Q00013Q001268000100043Q001202000200064Q008500020001000200062D0002001700013Q0004A13Q00170001001202000200074Q006E01036Q003A0002000200012Q00D93Q00017Q00073Q00030B3Q004661726D456E61626C656403043Q007469636B03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006C6F674661726D53652Q73696F6E446973636F726403153Q00D09ED182D187D191D18220D184D0B0D180D0BCD0B0023Q00806D4C4A4100123Q0012023Q00013Q000613012Q0004000100010004A13Q000400012Q00D93Q00013Q0012023Q00024Q00833Q0001000200122Q000100036Q00013Q000100122Q000200043Q00062Q0001000C000100020004A13Q000C00012Q00D93Q00013Q0012683Q00033Q0012EE000100053Q00122Q000200063Q00122Q000300076Q0001000300016Q00017Q000A3Q0003093Q006661726D506861736503063Q0073656172636803103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403123Q0073686F756C644661726D436F6E74696E756503133Q0072656672657368546172676574436F756E7473030F3Q0067657456616C696454617267657473028Q0003043Q0069646C65030B3Q006875625265737457616974012A3Q001280000100023Q00122Q000100013Q00122Q000100036Q0001000100014Q000100013Q00122Q000100046Q00015Q001202000200054Q006E01036Q009301020002000200062D0002002500013Q0004A13Q00250001001202000200064Q002001020001000100122Q000200076Q0002000100024Q000300023Q000E2Q00080016000100030004A13Q0016000100124D010300093Q001268000300014Q009D000200023Q001202000300054Q006E01046Q00930103000200020006130103001C000100010004A13Q001C00010004A13Q002500010012020003000A4Q006E01046Q00B3000500014Q00A301030005000200061301030023000100010004A13Q002300010004A13Q002500012Q000D2Q0100013Q0004A13Q0007000100124D010200093Q001268000200014Q000B00026Q009D000200024Q00D93Q00017Q00183Q00030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q00030D3Q006661726D54696D65546F74616C03043Q007469636B03093Q006661726D506861736503043Q0069646C6503093Q006661726D52756E4964026Q00F03F03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030A3Q0072657365744175746F46030C3Q0069676E6F72656444726F707303123Q0074656C65706F7274436F2Q6E656374696F6E030F3Q006D616E75616C53652Q6C546F6B656E030E3Q0073652Q6C496E50726F6772652Q73030A3Q006661726D546872656164030C3Q0073746F70536166654D6F6465003D3Q0012023Q00013Q00062D3Q000F00013Q0004A13Q000F00010012023Q00023Q000EDD0003000F00013Q0004A13Q000F00010012023Q00043Q0012432Q0100056Q00010001000200122Q000200026Q0001000100028Q000100124Q00043Q00124Q00033Q00124Q00024Q000D016Q0012763Q00013Q00124Q00073Q00124Q00063Q00124Q00083Q00206Q000900124Q00089Q003Q00124Q000A9Q003Q00124Q000B3Q00124D012Q000D3Q0012A63Q000C3Q00124Q000E3Q00122Q0001000F8Q0002000100124Q000E3Q00122Q000100108Q0002000100124Q000E3Q00122Q000100118Q000200010012023Q000E3Q0012092Q0100128Q000200019Q0000124Q00133Q00124Q00143Q00064Q003200013Q0004A13Q003200010012023Q000E3Q00024700016Q003A3Q000200012Q00357Q0012683Q00143Q0012023Q00153Q0020715Q000900124Q00159Q003Q00124Q00169Q003Q00124Q00173Q00124Q000E3Q00122Q000100188Q000200016Q00013Q00013Q00023Q0003123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400043Q0012023Q00013Q00202C014Q00022Q003A3Q000200012Q00D93Q00017Q00013Q00030D3Q006B692Q6C4661726D4C2Q6F707300033Q0012023Q00014Q0047012Q000100012Q00D93Q00017Q00083Q0003083Q0073746F704661726D030C3Q0073746F70536166654D6F6465030E3Q0073746F7043616D6572614C2Q6F7003183Q0064657374726F79426C6F636B65645A6F6E6556697375616C030C3Q007363722Q656E47756952656603063Q00506172656E7403053Q007063612Q6C03093Q007363722Q656E477569001E3Q0012023Q00014Q0047012Q000100010012023Q00024Q00933Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00053Q00064Q001300013Q0004A13Q001300010012023Q00053Q00203F014Q000600062D3Q001300013Q0004A13Q001300010012023Q00073Q00024700016Q003A3Q000200010004A13Q001D00010012023Q00083Q00062D3Q001D00013Q0004A13Q001D00010012023Q00083Q00203F014Q000600062D3Q001D00013Q0004A13Q001D00010012023Q00073Q000247000100014Q003A3Q000200012Q00D93Q00013Q00023Q00023Q00030C3Q007363722Q656E47756952656603073Q0044657374726F7900043Q0012023Q00013Q00202C014Q00022Q003A3Q000200012Q00D93Q00017Q00023Q0003093Q007363722Q656E47756903073Q0044657374726F7900043Q0012023Q00013Q00202C014Q00022Q003A3Q000200012Q00D93Q00017Q00023Q00030B3Q00736F6674436C65616E7570030D3Q00726573746F726543616D65726100053Q00121C3Q00018Q0001000100124Q00028Q000100016Q00017Q000E3Q00030D3Q006B692Q6C4661726D4C2Q6F7073030B3Q004661726D456E61626C6564030F3Q006661726D54696D655374617274656403043Q007469636B03103Q006C6173744661726D5265706F7274417403093Q006661726D52756E4964030D3Q007374617274536166654D6F646503123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374030A3Q006661726D54687265616403043Q007461736B03053Q00737061776E001B3Q00121C012Q00018Q000100016Q00013Q00124Q00023Q00124Q00048Q0001000200124Q00033Q00124Q00048Q0001000200124Q00053Q0012023Q00063Q0012AE000100076Q00010001000100122Q000100093Q00202Q00010001000A00202Q00010001000B00064100033Q000100012Q006E017Q00A32Q0100030002001268000100083Q0012020001000D3Q00203F2Q010001000E00064100020001000100012Q006E017Q00932Q01000200020012680001000C4Q00D93Q00013Q00023Q000B3Q0003123Q0073686F756C644661726D436F6E74696E756503093Q006661726D506861736503073Q00636F2Q6C65637403043Q007761697403043Q0073652Q6C2Q033Q0068756203063Q0073656172636803043Q006D696E6503113Q0063752Q72656E745461726765745061727403053Q007063612Q6C03103Q0074656C65706F7274546F54617267657400203Q0012023Q00014Q008100016Q0093012Q00020002000613012Q0006000100010004A13Q000600012Q00D93Q00013Q0012023Q00023Q002610012Q0015000100030004A13Q001500010012023Q00023Q002610012Q0015000100040004A13Q001500010012023Q00023Q002610012Q0015000100050004A13Q001500010012023Q00023Q002610012Q0015000100060004A13Q001500010012023Q00023Q002625012Q0016000100070004A13Q001600012Q00D93Q00013Q0012023Q00023Q002625012Q001F000100080004A13Q001F00010012023Q00093Q00062D3Q001F00013Q0004A13Q001F00010012023Q000A3Q0012020001000B4Q003A3Q000200012Q00D93Q00017Q000D3Q0003123Q0073686F756C644661726D436F6E74696E756503053Q007063612Q6C030D3Q00697343616E63656C452Q726F7203043Q007761726E03103Q005B4D415849204855425D206661726D3A03043Q007461736B03043Q0077616974026Q00E03F03093Q006661726D52756E496403113Q0063752Q72656E7454617267657450617274030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0069646C65002E4Q000D016Q001202000100014Q008100026Q00932Q010002000200062D0001002200013Q0004A13Q00220001001202000100023Q00064100023Q000100022Q00818Q006E017Q00A52Q01000200020006132Q010001000100010004A13Q00010001001202000300034Q006E010400024Q009301030002000200062D0003001300013Q0004A13Q001300010004A13Q00220001001202000300043Q0012CE000400056Q000500026Q00030005000100122Q000300016Q00048Q00030002000200062Q0003001D000100010004A13Q001D00010004A13Q00220001001202000300063Q00203F01030003000700124D010400084Q003A0003000200010004A13Q000100012Q008100015Q001202000200093Q00065F2Q01002D000100020004A13Q002D00012Q0035000100013Q0012680001000A3Q0012020001000B3Q0006132Q01002D000100010004A13Q002D000100124D2Q01000D3Q0012680001000C4Q00D93Q00013Q00013Q002F3Q0003103Q006D6179626552756E4175746F53652Q6C03123Q0073686F756C644661726D436F6E74696E756503123Q006D6179626552756E4661726D5265706F727403123Q0063617074757265487562506F736974696F6E030B3Q006875625265737457616974030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473028Q00030E3Q0072756E536561726368506861736503043Q007461736B03043Q0077616974029A5Q99C93F030E3Q007069636B42657374546172676574030A3Q006163746976654E6F646503043Q006E6F646503103Q006163746976655461726765744B696E6403043Q006B696E6403093Q006661726D506861736503043Q006D696E65030A3Q006F72626974416E676C65030A3Q0072657365744175746F46030B3Q00676574486974626F786573030F3Q00707573684661726D5761726E696E6703093Q006E6F5F686974626F7803193Q00D0A320D186D0B5D0BBD0B820D0BDD0B5D18220486974626F78026Q00E03F03103Q00636C6561724661726D5761726E696E6703113Q0063752Q72656E7454617267657450617274026Q00F03F03043Q007469636B026Q004E40030B3Q0069734E6F6465416C697665030B3Q007570646174654175746F46030B3Q006175746F46416374697665030C3Q00737475636B5F6D696E696E67032D3Q00D094D0BED0BBD0B3D0BE20D0BDD0B520D0BBD0BED0BCD0B0D0B5D182D181D18F20E2809420D0B6D0BCD1832046030A3Q00612Q7461636B50617274029A5Q99A93F03103Q0072656C656173654D6F757365486F6C6403053Q0073746F6E6503123Q0073652Q73696F6E53746F6E65734D696E656403113Q0073652Q73696F6E54722Q65734D696E656403103Q0077616974416E645363616E44726F7073030F3Q00636F2Q6C656374412Q6C44726F707303043Q0074722Q6503133Q0073746F704368617261637465724D6F74696F6E03143Q0072657475726E546F48756241667465724E6F646500BA3Q0012D43Q00016Q00019Q000002000100124Q00026Q00019Q000002000200064Q0009000100010004A13Q000900012Q00D93Q00013Q0012023Q00034Q0072012Q0001000100124Q00026Q00019Q000002000200064Q0011000100010004A13Q001100012Q00D93Q00014Q00813Q00013Q000613012Q001E000100010004A13Q001E00012Q000D012Q00014Q006D012Q00013Q00124Q00048Q0001000100124Q00056Q00019Q000002000200064Q001E000100010004A13Q001E00012Q00D93Q00013Q0012023Q00064Q00213Q0001000200122Q000100076Q0001000100014Q00015Q00262Q00010038000100080004A13Q00380001001202000100094Q005800028Q0001000200026Q00013Q00122Q000100026Q00028Q00010002000200062Q0001003100013Q0004A13Q003100012Q00682Q015Q0026252Q010036000100080004A13Q003600010012020001000A3Q00203F2Q010001000B00124D0102000C4Q003A0001000200012Q00D93Q00013Q001202000100074Q00472Q01000100010012020001000D4Q006E01026Q00932Q01000200020006132Q010042000100010004A13Q004200010012020002000A3Q00203F01020002000B00124D0103000C4Q003A0002000200012Q00D93Q00013Q00203F01020001000F0012030002000E3Q00202Q00020001001100122Q000200103Q00122Q000200133Q00122Q000200123Q00122Q000200083Q00122Q000200143Q00122Q000200156Q00020001000100122Q000200163Q0012020003000E4Q00930102000200022Q0068010300023Q0026250103005B000100080004A13Q005B0001001202000300173Q001230000400183Q00122Q000500196Q00030005000100122Q0003000A3Q00202Q00030003000B00122Q0004001A6Q0003000200016Q00013Q0012020003001B3Q001283010400186Q00030002000100202Q00030002001D00122Q0003001C3Q00122Q0003001E6Q00030001000200202Q00030003001F001202000400024Q008100056Q009301040002000200062D0004008700013Q0004A13Q008700010012020004001E4Q00850004000100020006D800040087000100030004A13Q00870001001202000400203Q0012020005000E4Q009301040002000200062D0004008700013Q0004A13Q00870001001202000400213Q0012020005000E4Q003A000400020001001202000400223Q00062D0004007C00013Q0004A13Q007C0001001202000400173Q00124D010500233Q00124D010600244Q00DF0004000600010004A13Q007F00010012020004001B3Q00124D010500234Q003A000400020001001202000400253Q0012630105001C6Q00040002000100122Q0004000A3Q00202Q00040004000B00122Q000500266Q00040002000100044Q00630001001202000400024Q008100056Q00930104000200020006130104008D000100010004A13Q008D00012Q00D93Q00013Q00124D010400083Q001284000400143Q00122Q000400276Q0004000100014Q000400043Q00122Q0004001C3Q00122Q000400103Q00262Q0004009A000100280004A13Q009A0001001202000400293Q00209500040004001D001268000400293Q0004A13Q009D00010012020004002A3Q00209500040004001D0012680004002A3Q0012020004002B3Q00121D0105000E6Q00068Q00040006000100122Q000400026Q00058Q00040002000200062Q000400A7000100010004A13Q00A700012Q00D93Q00013Q0012020004002C3Q0012740105000E6Q00068Q0004000600014Q000400043Q00122Q0004000E3Q00122Q0004002D3Q00122Q000400106Q000400043Q00122Q0004001C3Q00122Q0004002E6Q00040001000100122Q0004002F6Q00058Q00040002000200062Q000400B9000100010004A13Q00B900012Q00D93Q00014Q00D93Q00017Q00143Q0003073Q00656E61626C6564030B3Q004661726D456E61626C6564030B3Q006661726D5365636F6E6473030E3Q006765744661726D5365636F6E647303053Q00706861736503093Q006661726D506861736503053Q0074722Q6573030F3Q0063616368656454722Q65436F756E7403063Q0073746F6E657303103Q0063616368656453746F6E65436F756E7403053Q0064726F7073030F3Q0063616368656444726F70436F756E7403093Q0074722Q6544726F707303103Q0073652Q73696F6E54722Q6544726F7073030A3Q0073746F6E6544726F707303113Q0073652Q73696F6E53746F6E6544726F7073030A3Q0074722Q65734D696E656403113Q0073652Q73696F6E54722Q65734D696E6564030B3Q0073746F6E65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E656400184Q008F014Q000A00122Q000100023Q00104Q0001000100122Q000100046Q00010001000200104Q0003000100122Q000100063Q00104Q0005000100122Q000100083Q00104Q000700010012040001000A3Q00104Q0009000100122Q0001000C3Q00104Q000B000100122Q0001000E3Q00104Q000D000100122Q000100103Q00104Q000F000100122Q000100123Q00104Q00110001001202000100143Q001099012Q001300012Q009D3Q00024Q00D93Q00017Q000A3Q00030E3Q006661726D436865636B506175736503103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q00426C6F636B5569447572696E674661726D030B3Q004661726D456E61626C656403043Q0067656E7603153Q004D617869487562496E76556E626C6F636B656455692Q01030C3Q0073746F70536166654D6F646500134Q009B012Q00013Q00124Q00013Q00124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00053Q00064Q001200013Q0004A13Q001200010012023Q00063Q00062D3Q001200013Q0004A13Q001200010012023Q00073Q003021012Q000800090012023Q000A4Q0047012Q000100012Q00D93Q00017Q00073Q00030E3Q006661726D436865636B506175736503043Q0067656E7603153Q004D617869487562496E76556E626C6F636B65645569030B3Q004661726D456E61626C656403113Q00426C6F636B5569447572696E674661726D00030D3Q007374617274536166654D6F646500114Q00C77Q00124Q00013Q00124Q00023Q00206Q000300064Q001000013Q0004A13Q001000010012023Q00043Q00062D3Q001000013Q0004A13Q001000010012023Q00053Q00062D3Q001000013Q0004A13Q001000010012023Q00023Q003021012Q000300060012023Q00074Q0047012Q000100012Q00D93Q00017Q000C3Q0003043Q007479706503063Q00737472696E67034Q002Q033Q00737562026Q00F03F03013Q003C026Q00794003053Q006C6F77657203043Q0066696E6403093Q003C21646F63747970650003053Q003C68746D6C01273Q001202000100014Q006E01026Q00932Q01000200020026252Q01000D000100020004A13Q000D0001002610012Q000D000100030004A13Q000D000100202C2Q013Q000400124D010300053Q00124D010400054Q00A32Q01000400020026102Q01000F000100060004A13Q000F00012Q000D2Q016Q009D000100023Q00202C2Q013Q0004001263000300053Q00122Q000400076Q00010004000200202Q0001000100084Q00010002000200202Q00020001000900122Q0004000A3Q00122Q000500056Q000600016Q00020006000200262Q000200240001000B0004A13Q0024000100202C0102000100090012BD0004000C3Q00122Q000500056Q000600016Q00020006000200262Q000200240001000B0004A13Q002400012Q004000026Q000D010200014Q009D000200024Q00D93Q00017Q00063Q0003043Q0067616D6503073Q00482Q747047657403123Q006D6178692D6875622D75692E6C75613F763D03083Q00746F737472696E6703023Q006F7303043Q0074696D65000E3Q0012743Q00013Q00206Q00024Q00025Q00122Q000300033Q00122Q000400043Q00122Q000500053Q00202Q0005000500064Q000500016Q00043Q00024Q0002000200044Q000300018Q00039Q008Q00017Q003D3Q0003083Q0074656C656772616D030D3Q0054454C454752414D5F4C494E4B030A3Q007363726970744C696E6503013Q004C030B3Q007363726970745F6C696E65030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C6973745772617003083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D32026Q00F03F028Q00026Q00504003103Q004261636B67726F756E64436F6C6F723303063Q00434F4C4F525303053Q0070616E656C030F3Q00426F7264657253697A65506978656C03043Q00466F6E7403043Q00456E756D03063Q00476F7468616D03083Q005465787453697A65026Q002840030A3Q0054657874436F6C6F723303043Q0074657874030B3Q00546578745772612Q7065642Q0103043Q0054657874030C3Q005343524950545F5449544C4503013Q000A030E3Q00637265646974735F7468616E6B73030B3Q004C61796F75744F7264657203063Q00506172656E7403113Q006372656469747341626F75744C6162656C03093Q00612Q64436F726E6572026Q00204003093Q00554950612Q64696E67030A3Q0050612Q64696E67546F7003043Q005544696D026Q002440030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E675269676874030A3Q005465787442752Q746F6E026Q00444003063Q00612Q63656E74030A3Q00476F7468616D426F6C64026Q002A4003023Q00626703093Q0074675F62752Q746F6E030F3Q004175746F42752Q746F6E436F6C6F720100027Q0040030F3Q0063726564697473546742752Q746F6E030E3Q0072656769737465724C6F63616C65026Q002Q4003163Q004261636B67726F756E645472616E73706172656E637903053Q006D75746564026Q00084003113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E656374039C3Q00061301020004000100010004A13Q000400012Q000B00036Q006E010200033Q00203F01030002000100061301030008000100010004A13Q00080001001202000300023Q00203F0104000200030006130104000E000100010004A13Q000E0001001202000400043Q00124D010500054Q009301040002000200203F0105000100062Q001201068Q00050002000200202Q0006000100074Q000700056Q00060002000200122Q000700083Q00202Q00070007000900122Q0008000A6Q00070002000200122Q0008000C3Q00203F0108000800090012810109000D3Q00122Q000A000E3Q00122Q000B000E3Q00122Q000C000F6Q0008000C000200102Q0007000B000800202Q00080001001100202Q00080008001200102Q00070010000800302Q00070013000E001202000800153Q00201801080008001400202Q00080008001600102Q00070014000800302Q00070017001800202Q00080001001100202Q00080008001A00102Q00070019000800302Q0007001B001C00122Q0008001E3Q00122Q0009001F4Q006E010A00043Q001291010B001F3Q00122Q000C00043Q00122Q000D00206Q000C000200024Q00080008000C00102Q0007001D000800302Q00070021000D00102Q00070022000600122Q000700233Q00202Q0008000100242Q006E010900073Q00121F010A00256Q0008000A000100122Q000800083Q00202Q00080008000900122Q000900266Q00080002000200122Q000900283Q00202Q00090009000900122Q000A000E3Q00122Q000B00294Q00A30109000B000200109A01080027000900122Q000900283Q00202Q00090009000900122Q000A000E3Q00122Q000B00186Q0009000B000200102Q0008002A000900122Q000900283Q00202Q00090009000900122Q000A000E3Q00124D010B00184Q00EF0009000B000200102Q0008002B000900102Q00080022000700122Q000900083Q00202Q00090009000900122Q000A002C6Q00090002000200122Q000A000C3Q00202Q000A000A000900122Q000B000D3Q00124D010C000E3Q00124D010D000E3Q00124D010E002D4Q00A3010A000E00020010990109000B000A002019010A0001001100202Q000A000A002E00102Q00090010000A00302Q00090013000E00122Q000A00153Q00202Q000A000A001400202Q000A000A002F00102Q00090014000A00302Q00090017003000202Q000A0001001100202Q000A000A003100102Q00090019000A00122Q000A00043Q00122Q000B00326Q000A0002000200102Q0009001D000A00302Q00090033003400302Q00090021003500102Q00090022000600122Q000900363Q00122Q000A00376Q000B00093Q00122Q000C00326Q000A000C000100202Q000A000100244Q000B00093Q00122Q000C00256Q000A000C000100122Q000A00083Q00202Q000A000A000900122Q000B000A6Q000A0002000200122Q000B000C3Q00202Q000B000B000900122Q000C000D3Q00122Q000D000E3Q00122Q000E000E3Q00122Q000F00386Q000B000F000200102Q000A000B000B00302Q000A0039000D00122Q000B00153Q00202Q000B000B001400202Q000B000B001600102Q000A0014000B00302Q000A0017002900202Q000B0001001100202Q000B000B003A00102Q000A0019000B00302Q000A001B001C00102Q000A001D000300302Q000A0021003B00102Q000A0022000600202Q000B0009003C00202Q000B000B003D000641000D3Q000100022Q006E012Q00034Q006E012Q00094Q00DF000B000D00012Q00D93Q00013Q00013Q00073Q0003053Q007063612Q6C03043Q005465787403013Q004C03093Q0074675F636F7069656403043Q007461736B03053Q0064656C6179026Q00F83F00103Q0012023Q00013Q00064100013Q000100012Q00819Q003Q000200016Q00013Q00122Q000100033Q00122Q000200046Q00010002000200104Q0002000100124Q00053Q00206Q000600122Q000100073Q00064100020001000100012Q00813Q00014Q00DF3Q000200012Q00D93Q00013Q00023Q00013Q00030C3Q00736574636C6970626F61726400043Q0012023Q00014Q008100016Q003A3Q000200012Q00D93Q00017Q00043Q0003063Q00506172656E7403043Q005465787403013Q004C03093Q0074675F62752Q746F6E000A4Q00817Q00203F014Q000100062D3Q000900013Q0004A13Q000900012Q00817Q001202000100033Q00124D010200044Q00932Q0100020002001099012Q000200012Q00D93Q00017Q0027012Q00030F3Q00687562422Q6F74737472612Q706564030A3Q006C6F6164436F6E666967030D3Q006C6F61644C6F63616C654C696203103Q007265667265736850686173655465787403073Q0074616244656673030A3Q006765745461624465667303023Q007569030C3Q004D61786948756255494C696203063Q0063726561746503063Q00706C6179657203093Q00706C6179657247756903043Q0067656E7603053Q007469746C65030C3Q005343524950545F5449544C4503073Q006775694E616D6503083Q004755495F4E414D45030D3Q007361766564506F736974696F6E030A3Q0073617665645569506F73030F3Q0064656661756C74506F736974696F6E030E3Q0044454641554C545F55495F504F5303093Q007469746C6548696E7403013Q004C030A3Q007469746C655F68696E74030C3Q006869646548696E745465787403093Q00686964655F68696E7403083Q006C616E6775616765030A3Q0055694C616E677561676503103Q006F6E4C616E67756167654368616E6765030D3Q0073657455694C616E6775616765030E3Q0072656769737465724C6F63616C6503043Q0074616273030D3Q006B657953746174757354657874030E3Q006F6E53617665506F736974696F6E03123Q007363686564756C6553617665436F6E66696703093Q006F6E44657374726F79030A3Q0066752Q6C556E6C6F6164030D3Q006F6E43616D6572615374617274030F3Q00737461727443616D6572614C2Q6F7003063Q00434F4C4F5253030C3Q00636F6E74656E74506167657303093Q00612Q64436F726E657203093Q0073776974636854616203103Q006D616B6553656374696F6E5469746C65030A3Q006D616B65546F2Q676C65030A3Q006D616B65536C69646572030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C69737457726170030D3Q006D616B65466C6F7750616E656C030B3Q006D616B6553746174526F77030E3Q006D616B65466C6F77546F2Q676C6503093Q007363722Q656E47756903063Q007569522Q6F7403063Q007569426F6479030C3Q007363722Q656E477569526566030C3Q006D61696E4672616D6552656603133Q00666F726D617453652Q73696F6E54696D65556903103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503113Q0073652Q73696F6E537461744C6162656C73030C3Q007365744661726D537461746503083Q006D61696E50616765026Q00F03F030D3Q00636F6E74726F6C7350616E656C030E3Q0070616E656C5F636F6E74726F6C7303093Q0055495F4C41594F555403073Q0050414E454C5F57026Q006940028Q0003103Q00746F2Q676C655F6175746F7374617274030D3Q004175746F53746172744661726D02295C8FC2F528CC3F030F3Q00746F2Q676C655F6175746F6661726D027Q0040026Q00E03F030D3Q00746F2Q676C655F72656A6F696E030E3Q0052656A6F696E4175746F4C6F6164026Q00084002F6285C8FC2F5E83F030C3Q0073652Q73696F6E50616E656C030D3Q0070616E656C5F73652Q73696F6E03073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58030E3Q0053452Q53494F4E5F424F44595F5903053Q007068617365030B3Q00737461745F73746174757303053Q0074722Q6573030A3Q00737461745F74722Q657303063Q0073746F6E6573030B3Q00737461745F73746F6E657303043Q006C2Q6F7403093Q00737461745F6C2Q6F74026Q00104003043Q0074696D6503093Q00737461745F74696D65026Q00144003043Q006D6F646503093Q00737461745F6D6F6465026Q001840030C3Q00736C696465727350616E656C030F3Q0070616E656C5F74705F68656967687403063Q0046552Q4C5F57030E3Q00534C494445525F50414E454C5F4803063Q00524F57335F59030D3Q00534C494445525F424F44595F59030C3Q00736C696465725F74722Q6573026Q002840030E3Q0054656C65706F7274486569676874030D3Q00534C494445525F595F53544550030D3Q00736C696465725F73746F6E657303133Q0053746F6E6554656C65706F7274486569676874030B3Q007374617475734C6162656C03083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D3203073Q0056697369626C65010003063Q00506172656E7403093Q007365745363726F2Q6C03073Q0073657457726170030A3Q007365635F6D696E696E6703073Q006D696E65426F7803053Q004672616D65030A3Q004D494E455F424F585F4803163Q004261636B67726F756E645472616E73706172656E6379030B3Q004C61796F75744F72646572030C3Q00746F2Q676C655F6F72626974030C3Q004F72626974456E61626C6564030D3Q00544F2Q474C455F595F53544550030A3Q00746F2Q676C655F61696D030B3Q0041696D4174546172676574030B3Q00746F2Q676C655F666B657903073Q00557365464B6579030C3Q00746F2Q676C655F636C69636B03083Q00557365436C69636B030A3Q00736C6964657273426F78030D3Q00534C49444552535F424F585F4803123Q00736C696465725F6F726269745F73702Q6564026Q33D33F030A3Q004F7262697453702Q656403113Q00736C696465725F6F726269745F73697A65026Q003E40030D3Q004F726269744469616D65746572030A3Q007365635F73616665747903073Q0073616665426F78030A3Q00534146455F424F585F48030F3Q00746F2Q676C655F626C6F636B5F756903113Q00426C6F636B5569447572696E674661726D03133Q00746F2Q676C655F626C6F636B5F747261646573030B3Q00426C6F636B54726164657303093Q00626C6F636B48696E74026Q00324003043Q00466F6E7403043Q00456E756D03063Q00476F7468616D03083Q005465787453697A65026Q002440030A3Q0054657874436F6C6F723303053Q006D75746564030E3Q005465787458416C69676E6D656E7403043Q004C65667403043Q0054657874030D3Q0068696E745F626C6F636B5F7569030A3Q007365635F616E74697470026Q001C4003073Q007A6F6E65426F78026Q004640026Q002040030D3Q00746F2Q676C655F616E7469747003133Q00426C6F636B65645A6F6E6573456E61626C6564030D3Q007A6F6E65536C69646572426F78026Q00224003103Q00736C696465725F637562655F73697A65026Q003440026Q005E40030F3Q00426C6F636B65645A6F6E6553697A65030A3Q007A6F6E6542746E526F77026Q004240030C3Q007A6F6E65506C61636542746E030A3Q005465787442752Q746F6E03103Q004261636B67726F756E64436F6C6F723303053Q0070616E656C030F3Q00426F7264657253697A65506978656C030A3Q00476F7468616D426F6C64026Q00264003043Q0074657874030E3Q0062746E5F706C6163655F63756265030F3Q004175746F42752Q746F6E436F6C6F7203083Q007A6F6E6548696E74026Q002Q40030B3Q00546578745772612Q7065642Q01030B3Q0068696E745F616E7469747003113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E65637403073Q007365635F68756203063Q00687562426F78026Q002A40030F3Q00746F2Q676C655F6875625F77616974030E3Q0048756257616974456E61626C656403073Q0068756248696E74026Q003C40030D3Q0068696E745F6875625F77616974026Q002C4003083Q007365635F73652Q6C026Q002E4003073Q0073652Q6C426F78026Q005840026Q003040030F3Q00746F2Q676C655F6175746F73652Q6C030F3Q004175746F53652Q6C456E61626C656403113Q00736C696465725F73652Q6C5F636865636B03113Q0053652Q6C436865636B496E74657276616C030A3Q0073652Q6C42746E526F77026Q003140030D3Q006D616E75616C53652Q6C42746E03063Q00612Q63656E7403023Q006267030C3Q0062746E5F73652Q6C5F6E6F77030A3Q0073652Q6C537461747573034Q0003083Q0073652Q6C48696E7403093Q0068696E745F73652Q6C026Q003340030D3Q00646973636F72645363726F2Q6C030B3Q00646973636F726457726170030A3Q00776562682Q6F6B426F78025Q0080524003043Q0063617264030C3Q00776562682Q6F6B5469746C65026Q0034C003083Q00506F736974696F6E030D3Q00776562682Q6F6B5F7469746C65030C3Q00776562682Q6F6B496E70757403073Q0054657874426F7803103Q00436C656172546578744F6E466F637573030F3Q00506C616365686F6C6465725465787403243Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F3Q2E03113Q00506C616365686F6C646572436F6C6F723303123Q0055736572446973636F7264576562682Q6F6B030D3Q00646973636F726453746174757303103Q0063616E557365436F6E66696746696C6503103Q00776562682Q6F6B5F73617665645F6F6B03113Q00776562682Q6F6B5F73617665645F626164030B3Q00646973636F72644F707473025Q00406A4003113Q00646973636F72644F7074734C61796F7574030C3Q0055494C6973744C61796F757403073Q0050612Q64696E6703043Q005544696D03093Q00536F72744F72646572030A3Q00646973636F726450616403093Q00554950612Q64696E67030A3Q0050612Q64696E67546F70030D3Q0050612Q64696E67426F2Q746F6D030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E67526967687403163Q00746F2Q676C655F646973636F72645F7265706F72747303153Q00446973636F72645265706F727473456E61626C656403133Q00746F2Q676C655F646973636F72645F73746F7003103Q00446973636F72644C6F674F6E53746F7003133Q00746F2Q676C655F646973636F72645F73652Q6C03103Q00446973636F72644C6F674F6E53652Q6C030B3Q00696E74657276616C426F78026Q0020C0026Q004A4003173Q00736C696465725F646973636F72645F696E74657276616C03143Q00446973636F72645265706F72744D696E75746573030B3Q00646973636F726442746E7303073Q007465737442746E02B81E85EB51B8DE3F03103Q0062746E5F746573745F776562682Q6F6B03073Q007361766542746E02A4703D0AD7A3E03F03083Q0062746E5F73617665030B3Q00646973636F726448696E74026Q004840030C3Q00646973636F72645F68696E7403153Q00612Q706C79576562682Q6F6B46726F6D496E70757403093Q00466F6375734C6F737403163Q006275696C644D61786948756243726564697473546162030C3Q006F6E496E707574426567616E03083Q0066696E616C697A6503123Q00612Q706C794D6178694875624C6F63616C6503043Q007461736B03053Q00737061776E03173Q00757064617465426C6F636B65645A6F6E6556697375616C03133Q0068617350656E64696E6753652Q6C5374617465031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F74737472617003053Q00646566657203063Q00747970656F6603153Q004D617869487562526567697374657252656A6F696E03083Q0066756E6374696F6E03053Q007063612Q6C0085062Q0012023Q00013Q00062D3Q000400013Q0004A13Q000400012Q00D93Q00014Q000D012Q00013Q0012663Q00013Q00124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00068Q0001000200124Q00053Q0012023Q00083Q0020CD5Q00094Q00013Q001100122Q0002000A3Q00102Q0001000A000200122Q0002000B3Q00102Q0001000B000200122Q0002000C3Q00102Q0001000C000200122Q0002000E3Q00102Q0001000D0002001202000200103Q0010A70001000F000200122Q000200123Q00102Q00010011000200122Q000200143Q00102Q00010013000200122Q000200163Q00122Q000300176Q00020002000200102Q00010015000200122Q000200163Q00124D010300194Q008D00020002000200102Q00010018000200122Q0002001B3Q00102Q0001001A000200122Q0002001D3Q00102Q0001001C000200122Q0002001E3Q00102Q0001001E000200122Q000200053Q00102Q0001001F000200024700025Q00106200010020000200122Q000200223Q00102Q00010021000200122Q000200243Q00102Q00010023000200122Q000200263Q00102Q0001002500026Q0002000200124Q00073Q00124Q00073Q00206Q002700124Q00273Q00124Q00073Q00206Q002800124Q00283Q00124Q00073Q00206Q002900124Q00293Q00124Q00073Q00206Q002A00124Q002A3Q00124Q00073Q00206Q002B00124Q002B3Q00124Q00073Q00206Q002C00124Q002C3Q00124Q00073Q00206Q002D00124Q002D3Q00124Q00073Q00206Q002E00124Q002E3Q00124Q00073Q00206Q002F00124Q002F3Q00124Q00073Q00206Q003000124Q00303Q00124Q00073Q00206Q003100124Q00313Q00124Q00073Q00206Q003200124Q00323Q00124Q00073Q00206Q003300124Q00333Q00124Q00073Q00206Q003400124Q00343Q00124Q00073Q00206Q003500124Q00353Q00124Q00333Q00124Q00363Q00124Q00073Q00206Q003400124Q00373Q0002473Q00013Q002Q123Q00389Q003Q00124Q00399Q003Q00124Q003A9Q003Q00124Q003B3Q0002473Q00023Q001267012Q003C3Q00124Q00283Q00206Q003E00124Q003D3Q00124Q00303Q00122Q0001003D3Q00122Q000200163Q00122Q000300406Q00020002000200122Q000300413Q00203F010300030042001288000400433Q00122Q000500443Q00122Q000600446Q000700073Q00122Q000800408Q0008000200124Q003F3Q00124Q00323Q00122Q0001003F3Q00122Q000200163Q00124D010300454Q0093010200020002001202000300463Q000247000400033Q0012CA0005003E3Q00122Q000600473Q00122Q000700458Q0007000100124Q00323Q00122Q0001003F3Q00122Q000200163Q00122Q000300486Q0002000200024Q00035Q000247000400043Q001246010500493Q00122Q0006004A3Q00122Q000700488Q0007000200124Q003A3Q00124Q00323Q00122Q0001003F3Q00122Q000200163Q00122Q0003004B6Q00020002000200122Q0003004C3Q000247000400053Q0012370005004D3Q00122Q0006004E3Q00122Q0007004B8Q0007000100124Q00303Q00122Q0001003D3Q00122Q000200163Q00122Q000300506Q00020002000200122Q000300413Q00200500030003004200122Q000400413Q00202Q00040004005100122Q000500413Q00202Q00050005005200122Q000600443Q00122Q000700413Q00202Q00070007005300122Q000800508Q000800020012683Q004F3Q00125C3Q003B3Q00122Q000100313Q00122Q0002004F3Q00122Q000300163Q00122Q000400556Q00030002000200122Q0004003E3Q00122Q000500556Q00010005000200104Q0054000100125C3Q003B3Q00122Q000100313Q00122Q0002004F3Q00122Q000300163Q00122Q000400576Q00030002000200122Q000400493Q00122Q000500576Q00010005000200104Q0056000100125C3Q003B3Q00122Q000100313Q00122Q0002004F3Q00122Q000300163Q00122Q000400596Q00030002000200122Q0004004D3Q00122Q000500596Q00010005000200104Q0058000100125C3Q003B3Q00122Q000100313Q00122Q0002004F3Q00122Q000300163Q00122Q0004005B6Q00030002000200122Q0004005C3Q00122Q0005005B6Q00010005000200104Q005A000100125C3Q003B3Q00122Q000100313Q00122Q0002004F3Q00122Q000300163Q00122Q0004005E6Q00030002000200122Q0004005F3Q00122Q0005005E6Q00010005000200104Q005D000100125C3Q003B3Q00122Q000100313Q00122Q0002004F3Q00122Q000300163Q00122Q000400616Q00030002000200122Q000400623Q00122Q000500616Q00010005000200104Q006000010012023Q00303Q0012020001003D3Q001202000200163Q00124D010300644Q0093010200020002001202000300413Q00202C00030003006500122Q000400413Q00202Q00040004006600122Q000500443Q00122Q000600413Q00202Q00060006006700122Q000700413Q00202Q00070007006800122Q000800648Q000800020012683Q00633Q0012E83Q002D3Q00122Q000100633Q00122Q000200443Q00122Q000300163Q00122Q000400696Q00030002000200122Q000400443Q00122Q0005006A3Q00122Q0006006B3Q000247000700063Q00124B000800698Q0008000100124Q002D3Q00122Q000100633Q00122Q000200413Q00202Q00020002006C00122Q000300163Q00122Q0004006D6Q00030002000200122Q000400443Q00122Q0005006A3Q00122Q0006006E3Q000247000700073Q0012D10008006D8Q0008000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q006F3Q00124Q006F3Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500446Q00010005000200104Q0073000100124Q006F3Q00304Q0075007600124Q006F3Q00122Q0001003D3Q00104Q0077000100124Q002E3Q00122Q000100283Q00202Q0001000100496Q0002000200124Q00783Q00124Q002F3Q00122Q000100788Q0002000200124Q00793Q00124Q002B3Q00122Q000100793Q00122Q000200163Q00122Q0003007A6Q00020002000200122Q0003003E3Q00122Q0004007A8Q0004000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q007B3Q00124Q007B3Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500413Q00202Q00050005007D4Q00010005000200104Q0073000100124Q007B3Q00304Q007E003E00124Q007B3Q00304Q007F004900124Q007B3Q00122Q000100793Q00104Q0077000100124Q002C3Q00122Q0001007B3Q00122Q000200443Q00122Q000300163Q00122Q000400806Q00030002000200122Q000400813Q000247000500084Q009E010600063Q00122Q000700808Q0007000100124Q002C3Q00122Q0001007B3Q00122Q000200413Q00202Q00020002008200122Q000300163Q00122Q000400836Q00030002000200122Q000400843Q000247000500094Q000C000600063Q00122Q000700838Q0007000100124Q002C3Q00122Q0001007B3Q00122Q000200413Q00202Q00020002008200202Q00020002004900122Q000300163Q00122Q000400856Q00030002000200122Q000400863Q0002470005000A4Q000C000600063Q00122Q000700858Q0007000100124Q002C3Q00122Q0001007B3Q00122Q000200413Q00202Q00020002008200202Q00020002004D00122Q000300163Q00122Q000400876Q00030002000200122Q000400883Q0002470005000B4Q0066012Q0005000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00893Q00124Q00893Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00124D010300443Q001298000400443Q00122Q000500413Q00202Q00050005008A4Q00010005000200104Q0073000100124Q00893Q00304Q007E003E00124Q00893Q00304Q007F004D00124Q00893Q001202000100793Q001049012Q0077000100124Q002D3Q00122Q000100893Q00122Q000200443Q00122Q000300163Q00122Q0004008B6Q00030002000200122Q0004008C3Q00122Q0005004D3Q00122Q0006008D3Q0002470007000C3Q00124B0008008B8Q0008000100124Q002D3Q00122Q000100893Q00122Q000200413Q00202Q00020002006C00122Q000300163Q00122Q0004008E6Q00030002000200122Q0004005C3Q00122Q0005008F3Q00122Q000600903Q0002470007000D3Q0012780008008E8Q0008000100124Q002B3Q00122Q000100793Q00122Q000200163Q00122Q000300916Q00020002000200122Q0003005C3Q00122Q000400918Q000400010012023Q00703Q002031014Q007100122Q0001007C8Q0002000200124Q00923Q00124Q00923Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q001202000500413Q0020A00105000500934Q00010005000200104Q0073000100124Q00923Q00304Q007E003E00124Q00923Q00304Q007F005F00124Q00923Q00122Q000100793Q00104Q007700010012023Q002C3Q0012BC000100923Q00122Q000200443Q00122Q000300163Q00122Q000400946Q00030002000200122Q000400953Q0002470005000E4Q009E010600063Q00122Q000700948Q0007000100124Q002C3Q00122Q000100923Q00122Q000200413Q00202Q00020002008200122Q000300163Q00122Q000400966Q00030002000200122Q000400973Q0002470005000F4Q00A8000600063Q00122Q000700968Q0007000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00983Q00124Q00983Q00122Q000100743Q00203F2Q01000100710012320002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500996Q00010005000200104Q0073000100124Q00983Q00304Q007E003E00124Q00983Q00122Q0001009B3Q00203F2Q010001009A00203300010001009C00104Q009A000100124Q00983Q00304Q009D009E00124Q00983Q00122Q000100273Q00202Q0001000100A000104Q009F000100124Q00983Q00122Q0001009B3Q00203F2Q01000100A10020942Q01000100A200104Q00A1000100124Q00983Q00122Q000100163Q00122Q000200A46Q00010002000200104Q00A3000100124Q00983Q00304Q007F006200124Q00983Q001202000100793Q001099012Q007700010012023Q001E3Q001202000100983Q00124D010200A44Q0016012Q0002000100124Q002B3Q00122Q000100793Q00122Q000200163Q00122Q000300A56Q00020002000200122Q000300A63Q00122Q000400A58Q0004000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00A73Q00124Q00A73Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500A86Q00010005000200104Q0073000100124Q00A73Q00304Q007E003E00124Q00A73Q00304Q007F00A900124Q00A73Q00122Q000100793Q00104Q0077000100124Q002C3Q00122Q000100A73Q00122Q000200443Q00122Q000300163Q00122Q000400AA6Q00030002000200122Q000400AB3Q000247000500104Q004C010600063Q00122Q000700AA8Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00AC3Q00124Q00AC3Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500413Q00202Q00050005006C4Q00010005000200104Q0073000100124Q00AC3Q00304Q007E003E00124Q00AC3Q00304Q007F00AD00124Q00AC3Q00122Q000100793Q00104Q0077000100124Q002D3Q00122Q000100AC3Q00122Q000200443Q00122Q000300163Q00122Q000400AE6Q00030002000200122Q000400AF3Q00122Q000500B03Q00122Q000600B13Q000247000700113Q001257010800AE8Q0008000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00B23Q00124Q00B23Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q00B23Q00304Q007E003E00124Q00B23Q00304Q007F009E00124Q00B23Q00122Q000100793Q00104Q0077000100124Q00703Q00206Q007100122Q000100B58Q0002000200124Q00B43Q00124Q00B43Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q0004003E3Q00122Q000500446Q00010005000200104Q0073000100124Q00B43Q00122Q000100273Q00202Q0001000100B700104Q00B6000100124Q00B43Q00304Q00B8004400124Q00B43Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q00B43Q00304Q009D00BA00124Q00B43Q00122Q000100273Q00202Q0001000100BB00104Q009F000100124Q00B43Q00122Q000100163Q00122Q000200BC6Q00010002000200104Q00A3000100124Q00B43Q00304Q00BD007600124Q00B43Q00122Q000100B23Q00104Q0077000100124Q00293Q00122Q000100B43Q00122Q000200A98Q0002000100124Q001E3Q00122Q000100B43Q00122Q000200BC8Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00BE3Q00124Q00BE3Q00122Q000100743Q00202Q00010001007100124D0102003E3Q00126C000300443Q00122Q000400443Q00122Q000500BF6Q00010005000200104Q0073000100124Q00BE3Q00304Q007E003E00124Q00BE3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00BE3Q00304Q009D009E00124Q00BE3Q00122Q000100273Q00202Q0001000100A000104Q009F000100124Q00BE3Q00304Q00C000C100124Q00BE3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00BE3Q00122Q000100163Q00122Q000200C26Q00010002000200104Q00A3000100124Q00BE3Q00304Q007F00BA00124Q00BE3Q00122Q000100793Q00104Q0077000100124Q001E3Q00122Q000100BE3Q00122Q000200C28Q0002000100124Q00B43Q00206Q00C300206Q00C4000247000200124Q0016012Q0002000100124Q002B3Q00122Q000100793Q00122Q000200163Q00122Q000300C56Q00020002000200122Q0003006A3Q00122Q000400C58Q0004000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00C63Q00124Q00C63Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500A86Q00010005000200104Q0073000100124Q00C63Q00304Q007E003E00124Q00C63Q00304Q007F00C700124Q00C63Q00122Q000100793Q00104Q0077000100124Q002C3Q00122Q000100C63Q00122Q000200443Q00122Q000300163Q00122Q000400C86Q00030002000200122Q000400C93Q000247000500134Q00D5000600063Q00122Q000700C88Q0007000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00CA3Q00124Q00CA3Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500CB6Q00010005000200104Q0073000100124Q00CA3Q00304Q007E003E00124Q00CA3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00CA3Q00304Q009D009E00124Q00CA3Q00122Q000100273Q00202Q0001000100A000104Q009F000100124Q00CA3Q00304Q00C000C100124Q00CA3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00CA3Q00122Q000100163Q00122Q000200CC6Q00010002000200104Q00A3000100124Q00CA3Q00304Q007F00CD00124Q00CA3Q00122Q000100793Q00104Q0077000100124Q001E3Q00122Q000100CA3Q00122Q000200CC8Q0002000100124Q002B3Q00122Q000100793Q00122Q000200163Q00122Q000300CE6Q00020002000200122Q000300CF3Q00122Q000400CE8Q0004000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00D03Q00124Q00D03Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500D16Q00010005000200104Q0073000100124Q00D03Q00304Q007E003E00124Q00D03Q00304Q007F00D200124Q00D03Q00122Q000100793Q00104Q007700010012023Q002C3Q0012BC000100D03Q00122Q000200443Q00122Q000300163Q00122Q000400D36Q00030002000200122Q000400D43Q000247000500144Q0035000600063Q00124B000700D38Q0007000100124Q002D3Q00122Q000100D03Q00122Q000200413Q00202Q00020002008200122Q000300163Q00122Q000400D56Q00030002000200122Q000400AF3Q00122Q000500B03Q00122Q000600D63Q000247000700153Q001257010800D58Q0008000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00D73Q00124Q00D73Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q00D73Q00304Q007E003E00124Q00D73Q00304Q007F00D800124Q00D73Q00122Q000100793Q00104Q0077000100124Q00703Q00206Q007100122Q000100B58Q0002000200124Q00D93Q00124Q00D93Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q0004003E3Q00122Q000500446Q00010005000200104Q0073000100124Q00D93Q00122Q000100273Q00202Q0001000100DA00104Q00B6000100124Q00D93Q00304Q00B8004400124Q00D93Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q00D93Q00304Q009D00BA00124Q00D93Q00122Q000100273Q00202Q0001000100DB00104Q009F000100124Q00D93Q00122Q000100163Q00122Q000200DC6Q00010002000200104Q00A3000100124Q00D93Q00304Q00BD007600124Q00D93Q00122Q000100D73Q00104Q0077000100124Q00293Q00122Q000100D93Q00122Q000200A98Q0002000100124Q001E3Q00122Q000100D93Q00122Q000200DC8Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00DD3Q00124Q00DD3Q00122Q000100743Q00202Q0001000100710012320002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500D26Q00010005000200104Q0073000100124Q00DD3Q00304Q007E003E00124Q00DD3Q00122Q0001009B3Q00203F2Q010001009A00203300010001009C00104Q009A000100124Q00DD3Q00304Q009D009E00124Q00DD3Q00122Q000100273Q00202Q0001000100A000104Q009F000100124Q00DD3Q00122Q0001009B3Q00203F2Q01000100A100202A0001000100A200104Q00A1000100124Q00DD3Q00304Q00A300DE00124Q00DD3Q00304Q007F009900124Q00DD3Q00122Q000100793Q00104Q0077000100124Q00703Q00203F014Q007100128B2Q0100728Q0002000200124Q00DF3Q00124Q00DF3Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00126C000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q00DF3Q00304Q007E003E00124Q00DF3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00DF3Q00304Q009D009E00124Q00DF3Q00122Q000100273Q00202Q0001000100A000104Q009F000100124Q00DF3Q00304Q00C000C100124Q00DF3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00DF3Q00122Q000100163Q00122Q000200E06Q00010002000200104Q00A3000100124Q00DF3Q00304Q007F00E100124Q00DF3Q00122Q000100793Q00104Q0077000100124Q001E3Q00122Q000100DF3Q00122Q000200E08Q0002000100124Q00D93Q00206Q00C300206Q00C4000247000200164Q00D03Q0002000100124Q002E3Q00122Q000100283Q00202Q00010001004D6Q0002000200124Q00E23Q00124Q002F3Q00122Q000100E28Q0002000200124Q00E33Q00124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00E43Q00124Q00E43Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500E56Q00010005000200104Q0073000100124Q00E43Q00122Q000100273Q00202Q0001000100E600104Q00B6000100124Q00E43Q00304Q00B8004400124Q00E43Q00304Q007F003E00124Q00E43Q00122Q000100E33Q00104Q0077000100124Q00293Q00122Q000100E43Q00122Q0002009E8Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00E73Q00124Q00E73Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300E83Q00122Q000400443Q00122Q000500996Q00010005000200104Q0073000100124Q00E73Q00122Q000100743Q00202Q00010001007100122Q000200443Q00122Q0003009E3Q00122Q000400443Q00122Q000500A96Q00010005000200104Q00E9000100124Q00E73Q00304Q007E003E00124Q00E73Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q00E73Q00304Q009D00BA00124Q00E73Q00122Q000100273Q00202Q0001000100BB00104Q009F000100124Q00E73Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A100010012023Q00E73Q001286000100163Q00122Q000200EA6Q00010002000200104Q00A3000100124Q00E73Q00122Q000100E43Q00104Q0077000100124Q001E3Q00122Q000100E73Q00122Q000200EA8Q0002000100124Q00703Q00206Q007100122Q000100EC8Q0002000200124Q00EB3Q00124Q00EB3Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300E83Q00122Q000400443Q00122Q0005008F6Q00010005000200104Q0073000100124Q00EB3Q00122Q000100743Q00202Q00010001007100122Q000200443Q00122Q0003009E3Q00122Q000400443Q00122Q000500BF6Q00010005000200104Q00E9000100124Q00EB3Q00122Q000100273Q00202Q0001000100B700104Q00B6000100124Q00EB3Q00304Q00B8004400124Q00EB3Q00304Q00ED007600124Q00EB3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00EB3Q00304Q009D009E00124Q00EB3Q00122Q000100273Q00202Q0001000100BB00104Q009F000100124Q00EB3Q00304Q00EE00EF00124Q00EB3Q00122Q000100273Q00202Q0001000100A000104Q00F0000100124Q00EB3Q00122Q000100F13Q00104Q00A3000100124Q00EB3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00EB3Q00122Q000100E43Q00104Q0077000100124Q00293Q00122Q000100EB3Q00122Q000200A98Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00F23Q00124Q00F23Q001202000100743Q00208E00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500D26Q00010005000200104Q0073000100124Q00F23Q00304Q007E003E00124Q00F23Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00F23Q00304Q009D009E00124Q00F23Q00122Q000100273Q00202Q0001000100A000104Q009F000100124Q00F23Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00F23Q00122Q000100F36Q00010001000200062Q000100D304013Q0004A13Q00D30401001202000100163Q00124D010200F44Q00932Q01000200020006132Q0100D6040100010004A13Q00D60401001202000100163Q00124D010200F54Q00932Q0100020002001099012Q00A300010012653Q00F23Q00304Q007F004900124Q00F23Q00122Q000100E33Q00104Q0077000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00F63Q0012023Q00F63Q00123Q0100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q000500F76Q00010005000200104Q0073000100124Q00F63Q00122Q000100273Q00202A0001000100E600104Q00B6000100124Q00F63Q00304Q00B8004400124Q00F63Q00304Q007F004D00124Q00F63Q00122Q000100E33Q00104Q0077000100124Q00293Q001202000100F63Q0012420002009E8Q0002000100124Q00703Q00206Q007100122Q000100F98Q0002000200124Q00F83Q00124Q00F83Q00122Q000100FB3Q00202Q00010001007100124D010200443Q00124D0103005C4Q001E00010003000200104Q00FA000100124Q00F83Q00122Q0001009B3Q00202Q0001000100FC00202Q00010001007F00104Q00FC000100124Q00F83Q00122Q000100F63Q00104Q007700010012023Q00703Q0020C25Q007100122Q000100FE8Q0002000200124Q00FD3Q00124Q00FD3Q00122Q000100FB3Q00202Q00010001007100122Q000200443Q00122Q000300A96Q000100030002001099012Q00FF00010012453Q00FD3Q00122Q000100FB3Q00202Q00010001007100122Q000200443Q00122Q000300A96Q00010003000200105Q002Q0100124Q00FD3Q00122Q0001002Q012Q00122Q000200FB3Q00203F01020002007100128A000300443Q00122Q0004005C6Q0002000400026Q0001000200124Q00FD3Q00122Q00010002012Q00122Q000200FB3Q00202Q00020002007100122Q000300443Q00122Q0004005C4Q00A30102000400022Q0076012Q0001000200124Q00FD3Q00122Q000100F63Q00104Q0077000100124Q00323Q00122Q000100F63Q00122Q000200163Q00122Q00030003015Q00020002000200122Q00030004012Q000247000400173Q0012370005003E3Q00122Q000600473Q00122Q00070003017Q0007000100124Q00323Q00122Q000100F63Q00122Q000200163Q00122Q00030005015Q00020002000200122Q00030006012Q000247000400183Q001237000500493Q00122Q0006004A3Q00122Q00070005017Q0007000100124Q00323Q00122Q000100F63Q00122Q000200163Q00122Q00030007015Q00020002000200122Q00030008012Q000247000400193Q0012770005004D3Q00122Q0006004E3Q00122Q00070007017Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q0009012Q00124Q0009012Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q0003000A012Q00122Q000400443Q00122Q0005000B015Q00010005000200104Q0073000100124Q0009012Q00122Q0001003E3Q00104Q007E000100124Q0009012Q00122Q0001005C3Q00104Q007F000100124Q0009012Q00122Q000100F63Q00104Q0077000100124Q002D3Q00122Q00010009012Q00122Q000200443Q00122Q000300163Q00122Q0004000C015Q00030002000200122Q0004003E3Q00122Q000500B03Q00122Q0006000D012Q0002470007001A3Q0012420008000C017Q0008000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q000E012Q00124Q000E012Q00122Q000100743Q00202Q00010001007100124D0102003E3Q0012E9000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q000E012Q00122Q0001003E3Q00104Q007E000100124Q000E012Q00122Q0001005F3Q001099012Q007F000100127F012Q000E012Q00122Q000100E33Q00104Q0077000100124Q00703Q00206Q007100122Q000100B58Q0002000200124Q000F012Q00124Q000F012Q00122Q000100743Q00203F2Q010001007100122901020010012Q00122Q000300443Q00122Q0004003E3Q00122Q000500446Q00010005000200104Q0073000100124Q000F012Q00122Q000100273Q00202Q0001000100DA00104Q00B600010012023Q000F012Q0012692Q0100443Q00104Q00B8000100124Q000F012Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q000F012Q00122Q000100BA3Q00104Q009D00010012023Q000F012Q001270000100273Q00202Q0001000100DB00104Q009F000100124Q000F012Q00122Q000100163Q00122Q00020011015Q00010002000200104Q00A3000100124Q000F015Q00015Q001099012Q00BD0001001287012Q000F012Q00122Q0001000E012Q00104Q0077000100124Q00293Q00122Q0001000F012Q00122Q000200A98Q0002000100124Q001E3Q00122Q0001000F012Q00122Q00020011013Q00DF3Q000200010012023Q00703Q00203F014Q007100124D2Q0100B54Q0093012Q000200020012823Q0012012Q00124Q0012012Q00122Q000100743Q00202Q00010001007100122Q00020010012Q00122Q000300443Q00122Q0004003E3Q00122Q000500446Q00010005000200104Q0073000100124Q0012012Q00122Q000100743Q00202Q00010001007100122Q00020013012Q00122Q000300443Q00122Q000400443Q00122Q000500446Q00010005000200104Q00E9000100124Q0012012Q00122Q000100273Q00202Q0001000100B700104Q00B6000100124Q0012012Q00122Q000100443Q00104Q00B8000100124Q0012012Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q0012012Q00122Q000100BA3Q00104Q009D000100124Q0012012Q00122Q000100273Q00202Q0001000100BB00104Q009F000100124Q0012012Q00122Q000100163Q00122Q00020014015Q00010002000200104Q00A3000100124Q0012015Q00015Q00104Q00BD000100124Q0012012Q00122Q0001000E012Q00104Q0077000100124Q00293Q00122Q00010012012Q00122Q000200A98Q0002000100124Q001E3Q00122Q00010012012Q00122Q00020014017Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q0015012Q00124Q0015012Q00122Q000100743Q00202Q00010001007100122Q0002003E3Q00122Q000300443Q00122Q000400443Q00122Q00050016015Q00010005000200104Q0073000100124Q0015012Q00122Q0001003E3Q00104Q007E000100124Q0015012Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q0015012Q00124D2Q01009E3Q001084012Q009D000100124Q0015012Q00122Q000100273Q00202Q0001000100A000104Q009F000100124Q0015015Q000100013Q00104Q00C0000100124Q0015012Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q0015012Q00122Q000100163Q00122Q00020017015Q00010002000200104Q00A3000100124Q0015012Q00122Q000100623Q00104Q007F000100124Q0015012Q00122Q000100E33Q00104Q0077000100124Q001E3Q00122Q00010015012Q00122Q00020017017Q000200010002473Q001B3Q001207012Q0018012Q00124Q00EB3Q00122Q00010019019Q000100206Q00C40002470002001C4Q00DF3Q000200010012023Q0012012Q00203F014Q00C300202C014Q00C40002470002001D4Q00DF3Q000200010012023Q000F012Q00203F014Q00C300202C014Q00C40002470002001E4Q006D3Q0002000100124Q001A012Q00122Q000100283Q00122Q0002005C6Q0001000100024Q00023Q000400122Q000300273Q00102Q00020027000300122Q0003002E3Q00102Q0002002E00030012020003002F3Q0010920002002F000300122Q000300293Q00102Q0002002900036Q0002000100124Q00073Q00122Q0001001B019Q00010002470001001F4Q00ED3Q0002000100124Q00073Q00122Q0001001C019Q00016Q0001000100124Q001D017Q0001000100124Q001E012Q00122Q0001001F019Q0001000247000100204Q00513Q0002000100124Q0020017Q0001000100124Q0021017Q0001000200064Q006C06013Q0004A13Q006C06010012023Q0022013Q0047012Q000100010004A13Q007406010012023Q00463Q00062D3Q007406013Q0004A13Q007406010012023Q001E012Q00124D2Q010023013Q00C35Q0001000247000100214Q003A3Q000200010012023Q004C3Q00062D3Q008406013Q0004A13Q008406010012023Q0024012Q0012AA0001000C3Q00122Q00020025015Q0001000100026Q0002000200122Q00010026012Q00064Q0084060100010004A13Q008406010012023Q0027012Q0012020001000C3Q00124D01020025013Q00C30001000100022Q003A3Q000200012Q00D93Q00013Q00223Q00073Q0003043Q0067656E76030E3Q004D6178694875624B65794761746503063Q00747970656F6603103Q006765744B65795374617475735465787403083Q0066756E6374696F6E03013Q004C030A3Q006B65795F756E7061696400163Q0012023Q00013Q00203F014Q000200062D3Q001100013Q0004A13Q00110001001202000100033Q00203F01023Q00042Q00932Q01000200020026252Q010011000100050004A13Q0011000100203F2Q013Q00042Q00850001000100020006132Q010010000100010004A13Q00100001001202000100063Q00124D010200074Q00932Q01000200022Q009D000100023Q001202000100063Q00124D010200074Q002E000100024Q003D2Q016Q00D93Q00017Q00093Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D6174030B3Q002564D0BC2025303264D18103023Q00D18100153Q0012E53Q00018Q0001000200122Q000100023Q00202Q00010001000300202Q00023Q00044Q00010002000200202Q00023Q0004000E2Q00050010000100010004A13Q00100001001202000300063Q0020AF00030003000700122Q000400086Q000500016Q000600026Q000300066Q00036Q006E01035Q00124D010400094Q00600103000300042Q009D000300024Q00D93Q00017Q000D3Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D03113Q0073652Q73696F6E54722Q65734D696E6564028Q0003123Q0073652Q73696F6E53746F6E65734D696E6564030E3Q006765744661726D5365636F6E6473026Q00344003083Q0073746F704661726D03103Q00446973636F72644C6F674F6E53746F7003043Q007461736B03053Q00646566657201353Q00062D3Q001100013Q0004A13Q00110001001202000100013Q00062D0001000600013Q0004A13Q000600012Q00D93Q00014Q000D2Q0100013Q001297000100023Q00122Q000100036Q000200016Q000300016Q0001000300014Q00015Q00122Q000100023Q00122Q000100046Q00010001000100044Q00340001001202000100013Q0006132Q010015000100010004A13Q001500012Q00D93Q00013Q001202000100053Q000E8700060020000100010004A13Q00200001001202000100073Q000E8700060020000100010004A13Q00200001001202000100084Q0085000100010002000E8700090020000100010004A13Q002000012Q004000016Q000D2Q0100014Q0075010200013Q00122Q000200023Q00122Q000200036Q00038Q000400016Q0002000400014Q00025Q00122Q000200023Q00122Q0002000A6Q00020001000100062Q0001003400013Q0004A13Q003400010012020002000B3Q00062D0002003400013Q0004A13Q003400010012020002000C3Q00203F01020002000D00024700036Q003A0002000200012Q00D93Q00013Q00013Q00013Q0003053Q007063612Q6C00043Q0012023Q00013Q00024700016Q003A3Q000200012Q00D93Q00013Q00013Q00033Q0003153Q006C6F674661726D53652Q73696F6E446973636F7264031D3Q00D0A4D0B0D180D0BC20D0BED181D182D0B0D0BDD0BED0B2D0BBD0B5D0BD023Q008087E96C4100053Q0012EE3Q00013Q00122Q000100023Q00122Q000200038Q000200016Q00017Q00023Q00030D3Q004175746F53746172744661726D03123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q0003103Q006661726D546F2Q676C6553696C656E74030C3Q007365744661726D537461746501083Q001202000100013Q00062D0001000400013Q0004A13Q000400012Q00D93Q00013Q001202000100024Q006E01026Q003A0001000200012Q00D93Q00017Q00073Q00030E3Q0052656A6F696E4175746F4C6F616403123Q007363686564756C6553617665436F6E66696703063Q00747970656F6603043Q0067656E7603153Q004D617869487562526567697374657252656A6F696E03083Q0066756E6374696F6E03053Q007063612Q6C01103Q0012683Q00013Q001202000100024Q00472Q010001000100062D3Q000F00013Q0004A13Q000F0001001202000100033Q001202000200043Q00203F0102000200052Q00932Q01000200020026252Q01000F000100060004A13Q000F0001001202000100073Q001202000200043Q00203F0102000200052Q003A0001000200012Q00D93Q00017Q00023Q00030E3Q0054656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q0003133Q0053746F6E6554656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q00030C3Q004F72626974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q00030B3Q0041696D417454617267657403123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q0003073Q00557365464B657903123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00033Q0003083Q00557365436C69636B03103Q0072656C656173654D6F757365486F6C6403123Q007363686564756C6553617665436F6E66696701083Q0012683Q00013Q00062D3Q000500013Q0004A13Q00050001001202000100024Q00472Q0100010001001202000100034Q00472Q01000100012Q00D93Q00017Q00023Q00030A3Q004F7262697453702Q656403123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q00030D3Q004F726269744469616D6574657203123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q0003113Q00426C6F636B5569447572696E674661726D03123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00053Q00030B3Q00426C6F636B547261646573030B3Q004661726D456E61626C6564030A3Q007363616E54726164657303093Q00706C6179657247756903123Q007363686564756C6553617665436F6E666967010A3Q0012683Q00013Q001202000100023Q00062D0001000700013Q0004A13Q00070001001202000100033Q001202000200044Q003A000100020001001202000100054Q00472Q01000100012Q00D93Q00017Q00033Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E66696701063Q0012683Q00013Q00121C000100026Q00010001000100122Q000100036Q0001000100016Q00017Q00053Q00030F3Q00426C6F636B65645A6F6E6553697A6503043Q006D61746803053Q00666C2Q6F7203173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E666967010A3Q0012F5000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q00010001000100122Q000100056Q0001000100016Q00017Q00093Q0003163Q00736574426C6F636B65645A6F6E654174506C61796572030C3Q007A6F6E65506C61636542746E03043Q005465787403013Q004C030F3Q0062746E5F637562655F706C6163656403043Q007461736B03053Q0064656C6179026Q33F33F03103Q0062746E5F6E6F5F63686172616374657200153Q0012023Q00014Q00853Q0001000200062D3Q000F00013Q0004A13Q000F00010012023Q00023Q00120F2Q0100043Q00122Q000200056Q00010002000200104Q0003000100124Q00063Q00206Q000700122Q000100083Q00024700026Q00DF3Q000200010004A13Q001400010012023Q00023Q001202000100043Q00124D010200094Q00932Q0100020002001099012Q000300012Q00D93Q00013Q00013Q00053Q00030C3Q007A6F6E65506C61636542746E03063Q00506172656E7403043Q005465787403013Q004C030E3Q0062746E5F706C6163655F63756265000A3Q0012023Q00013Q00203F014Q000200062D3Q000900013Q0004A13Q000900010012023Q00013Q001202000100043Q00124D010200054Q00932Q0100020002001099012Q000300012Q00D93Q00017Q00023Q00030E3Q0048756257616974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q00030F3Q004175746F53652Q6C456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00043Q0003113Q0053652Q6C436865636B496E74657276616C03043Q006D61746803053Q00666C2Q6F7203123Q007363686564756C6553617665436F6E66696701083Q0012232Q0100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q0001000100016Q00017Q000D3Q00030E3Q0073652Q6C496E50726F6772652Q73030A3Q0073652Q6C53746174757303043Q005465787403013Q004C03093Q0073652Q6C5F62757379030A3Q0054657874436F6C6F723303063Q00434F4C4F52532Q033Q00726564030D3Q006D616E75616C53652Q6C42746E030B3Q0062746E5F73652Q6C696E6703073Q0073652Q6C5F747003053Q006D75746564030D3Q0072756E4D616E75616C53652Q6C001F3Q0012023Q00013Q00062D3Q000D00013Q0004A13Q000D00010012023Q00023Q001202000100043Q00124D010200054Q00932Q0100020002001099012Q000300010012223Q00023Q00122Q000100073Q00202Q00010001000800104Q000600016Q00013Q0012023Q00093Q00124F2Q0100043Q00122Q0002000A6Q00010002000200104Q0003000100124Q00023Q00122Q000100043Q00122Q0002000B6Q00010002000200104Q0003000100124Q00023Q00122Q000100073Q00202Q00010001000C00104Q0006000100124Q000D3Q00024700016Q003A3Q000200012Q00D93Q00013Q00013Q000B3Q00030D3Q006D616E75616C53652Q6C42746E03043Q005465787403013Q004C030C3Q0062746E5F73652Q6C5F6E6F77030A3Q0073652Q6C53746174757303093Q0073652Q6C5F646F6E65030A3Q0073652Q6C5F652Q726F72030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q00726564021E3Q001220000200013Q00122Q000300033Q00122Q000400046Q00030002000200102Q00020002000300122Q000200053Q00062Q00030012000100010004A13Q0012000100062D3Q000F00013Q0004A13Q000F0001001202000300033Q00124D010400064Q009301030002000200061301030012000100010004A13Q00120001001202000300033Q00124D010400074Q0093010300020002001099010200020003001202000200053Q00062D3Q001A00013Q0004A13Q001A0001001202000300093Q00203F01030003000A0006130103001C000100010004A13Q001C0001001202000300093Q00203F01030003000B0010990102000800032Q00D93Q00017Q00053Q0003153Q00446973636F72645265706F727473456E61626C656403143Q004641524D5F5245504F52545F494E54455256414C03143Q00446973636F72645265706F72744D696E75746573026Q004E4003113Q0073617665446973636F7264436F6E66696701073Q001214012Q00013Q00122Q000100033Q00202Q00010001000400122Q000100023Q00122Q000100056Q0001000100016Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53746F7003113Q0073617665446973636F7264436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53652Q6C03113Q0073617665446973636F7264436F6E66696701043Q0012683Q00013Q001202000100024Q00472Q01000100012Q00D93Q00017Q00063Q0003143Q00446973636F72645265706F72744D696E7574657303043Q006D61746803053Q00666C2Q6F7203143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003113Q0073617665446973636F7264436F6E666967010B3Q00125A2Q0100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100013Q00202Q00010001000500122Q000100043Q00122Q000100066Q0001000100016Q00017Q00083Q0003123Q0055736572446973636F7264576562682Q6F6B030C3Q00776562682Q6F6B496E70757403043Q005465787403043Q006773756203043Q005E25732B034Q0003043Q0025732B2403113Q0073617665446973636F7264436F6E666967000E3Q0012FF3Q00023Q00206Q000300206Q000400122Q000200053Q00122Q000300068Q0003000200206Q000400122Q000200073Q00122Q000300068Q0003000200124Q00013Q00124Q00088Q000100016Q00017Q00013Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757400033Q0012023Q00014Q0047012Q000100012Q00D93Q00017Q000B3Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E707574030D3Q00646973636F726453746174757303043Q005465787403013Q004C030D3Q00646973636F72645F7361766564030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E7403043Q007461736B03053Q0064656C6179027Q004000113Q001277012Q00018Q0001000100124Q00023Q00122Q000100043Q00122Q000200056Q00010002000200104Q0003000100124Q00023Q00122Q000100073Q00202Q000100010008001099012Q000600010012023Q00093Q00203F014Q000A00124D2Q01000B3Q00024700026Q00DF3Q000200012Q00D93Q00013Q00013Q00063Q00030D3Q00646973636F726453746174757303063Q00506172656E7403173Q00757064617465446973636F726453746174757354657874030A3Q0054657874436F6C6F723303063Q00434F4C4F525303053Q006D75746564000B3Q0012023Q00013Q00203F014Q000200062D3Q000A00013Q0004A13Q000A00010012023Q00034Q00C03Q0001000100124Q00013Q00122Q000100053Q00202Q00010001000600104Q000400012Q00D93Q00017Q00163Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757403103Q0073656E64446973636F7264456D62656403153Q006765744661726D446973636F7264576562682Q6F6B03113Q00D0A2D0B5D181D182204D41584920485542023Q00806D4C4A4103043Q006E616D6503103Q00D09FD180D0BED0B2D0B5D180D0BAD0B003053Q0076616C756503393Q00D095D181D0BBD0B820D0B2D0B8D0B4D0B8D188D18C20D18DD182D0BE20E2809420776562682Q6F6B20D180D0B0D0B1D0BED182D0B0D0B5D18203063Q00696E6C696E65010003103Q00D098D0BDD182D0B5D180D0B2D0B0D0BB03083Q00746F737472696E6703143Q00446973636F72645265706F72744D696E7574657303073Q0020D0BCD0B8D0BD2Q01030D3Q00646973636F726453746174757303043Q0054657874030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q0072656400243Q00124E012Q00018Q0001000100124Q00023Q00122Q000100036Q00010001000200122Q000200043Q00122Q000300056Q000400026Q00053Q000300302Q00050006000700302Q00050008000900302Q0005000A000B4Q00063Q000300302Q00060006000C00122Q0007000D3Q00122Q0008000E6Q00070002000200122Q0008000F6Q00070007000800102Q00060008000700302Q0006000A00104Q0004000200012Q004E3Q00040001001202000200113Q001099010200120001001202000200113Q00062D3Q002000013Q0004A13Q00200001001202000300143Q00203F01030003001500061301030022000100010004A13Q00220001001202000300143Q00203F0103000300160010990102001300032Q00D93Q00017Q00093Q0003073Q004B6579436F646503063Q00484F544B455903043Q007469636B03043Q0067656E7603133Q004D6178694875624C617374486F746B65794174028Q0002CD5QCCDC3F030C3Q007365744661726D5374617465030B3Q004661726D456E61626C656401173Q00203F2Q013Q0001001202000200023Q00061800010005000100020004A13Q000500012Q00D93Q00013Q001202000100034Q0085000100010002001202000200043Q00203F0102000200050006130102000C000100010004A13Q000C000100124D010200064Q007301020001000200263A01020010000100070004A13Q001000012Q00D93Q00013Q001202000200043Q00101B01020005000100122Q000200083Q00122Q000300096Q000300036Q0002000200016Q00017Q00263Q0003093Q007363722Q656E47756903063Q00506172656E74030A3Q006163746976654E6F646503093Q006661726D506861736503043Q007761697403073Q00636F2Q6C656374030F3Q0063616368656444726F70436F756E74030D3Q0066696E6444726F70734E656172028Q00030A3Q0050484153455F54455854030B3Q006175746F46416374697665030D3Q0020C2B720D0B0D0B2D182D0BE46034Q00030F3Q006765744661726D4D6F64655465787403113Q0073652Q73696F6E537461744C6162656C7303053Q00706861736503043Q005465787403053Q0074722Q657303083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q0073746F6E657303123Q0073652Q73696F6E53746F6E65734D696E656403043Q006C2Q6F7403043Q0074696D6503133Q00666F726D617453652Q73696F6E54696D65556903043Q006D6F6465030B3Q007374617475734C6162656C03073Q0056697369626C65030F3Q004175746F53652Q6C456E61626C656403143Q0067657453652Q6C5472692Q676572416D6F756E7403063Q00737472696E6703063Q00666F726D617403083Q00207C2025733A256403233Q002573207C20D0B43A256420D0BA3A2564207C202573207C20D0BBD183D1823A25642573030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403043Q007461736B029A5Q99D93F00823Q0012023Q00013Q00203F014Q000200062D3Q008100013Q0004A13Q008100010012023Q00033Q00062D3Q001300013Q0004A13Q001300010012023Q00043Q002610012Q000D000100050004A13Q000D00010012023Q00043Q002625012Q0013000100060004A13Q001300010012023Q00083Q00121E2Q0100038Q000200029Q0000124Q00073Q00044Q0015000100124D012Q00093Q0012683Q00073Q0012023Q000A3Q001202000100044Q00C35Q0001000613012Q001B000100010004A13Q001B00010012023Q00043Q0012020001000B3Q00062D0001002100013Q0004A13Q0021000100124D2Q01000C3Q0006132Q010022000100010004A13Q0022000100124D2Q01000D3Q0012020002000E4Q00850002000100020012020003000F3Q00203F01030003001000062D0003002E00013Q0004A13Q002E00010012020003000F3Q0020320103000300104Q00048Q000500016Q00040004000500102Q0003001100040012020003000F3Q00203F01030003001200062D0003003800013Q0004A13Q003800010012020003000F3Q00208E01030003001200122Q000400133Q00122Q000500146Q00040002000200102Q0003001100040012020003000F3Q00203F01030003001500062D0003004200013Q0004A13Q004200010012020003000F3Q00208E01030003001500122Q000400133Q00122Q000500166Q00040002000200102Q0003001100040012020003000F3Q00203F01030003001700062D0003004C00013Q0004A13Q004C00010012020003000F3Q00208E01030003001700122Q000400133Q00122Q000500076Q00040002000200102Q0003001100040012020003000F3Q00203F01030003001800062D0003005500013Q0004A13Q005500010012020003000F3Q00203F010300030018001202000400194Q00850004000100020010990103001100040012020003000F3Q00203F01030003001A00062D0003005C00013Q0004A13Q005C00010012020003000F3Q00203F01030003001A0010990103001100020012020003001B3Q00062D0003007C00013Q0004A13Q007C00010012020003001B3Q00203F01030003001C00062D0003007C00013Q0004A13Q007C000100124D0103000D3Q0012020004001D3Q00062D0004007000013Q0004A13Q007000010012020004001E4Q008900040001000500122Q0006001F3Q00202Q00060006002000122Q000700216Q000800056Q000900046Q0006000900024Q000300063Q0012020004001B3Q0012360105001F3Q00202Q00050005002000122Q000600226Q000700023Q00122Q000800233Q00122Q000900246Q000A5Q00122Q000B00076Q000C00036Q0005000C000200102Q000400110005001202000300253Q00203F01030003000500124D010400264Q003A0003000200010004A15Q00012Q00D93Q00017Q00033Q0003103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C65030C3Q007365744661726D5374617465000C4Q003E3Q00013Q00124Q00013Q00124Q00026Q000100016Q000200018Q000200019Q0000124Q00013Q00124Q00036Q000100018Q000200016Q00017Q00093Q00030C3Q00656E73757265506C6179657203043Q007761726E03393Q005B4D415849204855425D20D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD0BED0BBD183D187D0B8D182D18C20506C6179657247756903053Q007072696E74031D3Q005B4D415849204855425D20D0B7D0B0D0BFD183D181D0BA2055493Q2E03053Q007063612Q6C03103Q00622Q6F7473747261704D617869487562030F3Q00687562422Q6F74737472612Q70656403273Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0B7D0B0D0BFD183D181D0BAD0B03A00173Q0012023Q00014Q00853Q00010002000613012Q0008000100010004A13Q000800010012023Q00023Q00124D2Q0100034Q003A3Q000200012Q00D93Q00013Q0012023Q00043Q00120A000100058Q0002000100124Q00063Q00122Q000100078Q0002000100064Q0016000100010004A13Q001600012Q000D01025Q00128A010200083Q00122Q000200023Q00122Q000300096Q000400016Q0002000400012Q00D93Q00017Q00033Q00030F3Q00687562422Q6F74737472612Q706564030B3Q00736F6674436C65616E7570030D3Q006C61756E63684D61786948756200084Q0097016Q00124Q00013Q00124Q00028Q0001000100124Q00038Q00019Q008Q00017Q00043Q0003053Q007063612Q6C030D3Q006C61756E63684D61786948756203043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012023Q00013Q001202000100024Q00A5012Q00020001000613012Q0009000100010004A13Q00090001001202000200033Q00124D010300044Q006E010400014Q00DF0002000400012Q00D93Q00017Q00", GetFEnv(), ...);
