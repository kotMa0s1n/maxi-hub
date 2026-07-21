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
				if (Enum <= 194) then
					if (Enum <= 96) then
						if (Enum <= 47) then
							if (Enum <= 23) then
								if (Enum <= 11) then
									if (Enum <= 5) then
										if (Enum <= 2) then
											if (Enum <= 0) then
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
											elseif (Enum == 1) then
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
										elseif (Enum <= 3) then
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
										elseif (Enum > 4) then
											Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
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
									elseif (Enum <= 8) then
										if (Enum <= 6) then
											local A = Inst[2];
											Stk[A] = Stk[A](Stk[A + 1]);
										elseif (Enum > 7) then
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
										else
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
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
										end
									elseif (Enum <= 9) then
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
									elseif (Enum == 10) then
										if (Inst[2] < Stk[Inst[4]]) then
											VIP = Inst[3];
										else
											VIP = VIP + 1;
										end
									else
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
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
									end
								elseif (Enum <= 17) then
									if (Enum <= 14) then
										if (Enum <= 12) then
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
										elseif (Enum == 13) then
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
											Stk[Inst[2]] = Inst[3];
											VIP = VIP + 1;
											Inst = Instr[VIP];
											Stk[Inst[2]] = Env[Inst[3]];
										end
									elseif (Enum <= 15) then
										local A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
									elseif (Enum > 16) then
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
									end
								elseif (Enum <= 20) then
									if (Enum <= 18) then
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
									elseif (Enum == 19) then
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
									end
								elseif (Enum <= 21) then
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
								elseif (Enum > 22) then
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
							elseif (Enum <= 35) then
								if (Enum <= 29) then
									if (Enum <= 26) then
										if (Enum <= 24) then
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
										elseif (Enum == 25) then
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
											Stk[Inst[2]][Inst[3]] = Inst[4];
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
									elseif (Enum <= 27) then
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
									elseif (Enum > 28) then
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
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									end
								elseif (Enum <= 32) then
									if (Enum <= 30) then
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
									elseif (Enum == 31) then
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
									end
								elseif (Enum <= 33) then
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
								elseif (Enum == 34) then
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
								elseif (Stk[Inst[2]] < Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 41) then
								if (Enum <= 38) then
									if (Enum <= 36) then
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
									elseif (Enum == 37) then
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
									else
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
									end
								elseif (Enum <= 39) then
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
								elseif (Enum > 40) then
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
							elseif (Enum <= 44) then
								if (Enum <= 42) then
									if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 43) then
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
							elseif (Enum <= 45) then
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
							elseif (Enum > 46) then
								local B;
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
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
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
						elseif (Enum <= 71) then
							if (Enum <= 59) then
								if (Enum <= 53) then
									if (Enum <= 50) then
										if (Enum <= 48) then
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
										elseif (Enum == 49) then
											local A = Inst[2];
											Stk[A](Stk[A + 1]);
										else
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
										end
									elseif (Enum <= 51) then
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
									elseif (Enum == 52) then
										if (Stk[Inst[2]] < Stk[Inst[4]]) then
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
								elseif (Enum <= 56) then
									if (Enum <= 54) then
										Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
									elseif (Enum > 55) then
										Stk[Inst[2]] = Upvalues[Inst[3]];
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
								elseif (Enum <= 57) then
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
								elseif (Enum > 58) then
									local A;
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
									Stk[Inst[2]] = Inst[3];
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
							elseif (Enum <= 65) then
								if (Enum <= 62) then
									if (Enum <= 60) then
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
									elseif (Enum > 61) then
										local A = Inst[2];
										local Results = {Stk[A]()};
										local Limit = Inst[4];
										local Edx = 0;
										for Idx = A, Limit do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
									else
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
									end
								elseif (Enum <= 63) then
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
								elseif (Enum == 64) then
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
								end
							elseif (Enum <= 68) then
								if (Enum <= 66) then
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
								elseif (Enum == 67) then
									Stk[Inst[2]] = Inst[3];
								else
									local B;
									local A;
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
								end
							elseif (Enum <= 69) then
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
							elseif (Enum == 70) then
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
							end
						elseif (Enum <= 83) then
							if (Enum <= 77) then
								if (Enum <= 74) then
									if (Enum <= 72) then
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
									elseif (Enum == 73) then
										Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
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
									end
								elseif (Enum <= 75) then
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
								elseif (Enum > 76) then
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
							elseif (Enum <= 80) then
								if (Enum <= 78) then
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
								elseif (Enum > 79) then
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
								end
							elseif (Enum <= 81) then
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
							elseif (Enum > 82) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A]());
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
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
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Env[Inst[3]] = Stk[Inst[2]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 89) then
							if (Enum <= 86) then
								if (Enum <= 84) then
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
								elseif (Enum > 85) then
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
								elseif (Stk[Inst[2]] <= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 87) then
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
							elseif (Enum > 88) then
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
							else
								do
									return;
								end
							end
						elseif (Enum <= 92) then
							if (Enum <= 90) then
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
							elseif (Enum == 91) then
								Stk[Inst[2]] = Stk[Inst[3]] - Inst[4];
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
						elseif (Enum <= 94) then
							if (Enum > 93) then
								local B = Stk[Inst[4]];
								if B then
									VIP = VIP + 1;
								else
									Stk[Inst[2]] = B;
									VIP = Inst[3];
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
							end
						elseif (Enum > 95) then
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
					elseif (Enum <= 145) then
						if (Enum <= 120) then
							if (Enum <= 108) then
								if (Enum <= 102) then
									if (Enum <= 99) then
										if (Enum <= 97) then
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
										elseif (Enum == 98) then
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
											Stk[Inst[2]] = Inst[3];
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
										end
									elseif (Enum <= 100) then
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
									elseif (Enum == 101) then
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
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
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
									end
								elseif (Enum <= 105) then
									if (Enum <= 103) then
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
										Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									elseif (Enum == 104) then
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
									else
										local B;
										local T;
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
										Stk[Inst[2]][Inst[3]] = Inst[4];
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
								elseif (Enum <= 106) then
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
								elseif (Enum > 107) then
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
							elseif (Enum <= 114) then
								if (Enum <= 111) then
									if (Enum <= 109) then
										local A = Inst[2];
										local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
										Top = (Limit + A) - 1;
										local Edx = 0;
										for Idx = A, Top do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
									elseif (Enum > 110) then
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
								elseif (Enum <= 112) then
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
								elseif (Enum > 113) then
									Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
								else
									local A = Inst[2];
									do
										return Stk[A], Stk[A + 1];
									end
								end
							elseif (Enum <= 117) then
								if (Enum <= 115) then
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
								elseif (Enum > 116) then
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
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								end
							elseif (Enum <= 118) then
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
							elseif (Enum == 119) then
								local B;
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
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
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
						elseif (Enum <= 132) then
							if (Enum <= 126) then
								if (Enum <= 123) then
									if (Enum <= 121) then
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
									elseif (Enum > 122) then
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
										Stk[Inst[2]] = Inst[3];
										VIP = VIP + 1;
										Inst = Instr[VIP];
										Stk[Inst[2]] = Env[Inst[3]];
									end
								elseif (Enum <= 124) then
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
								elseif (Enum > 125) then
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
								elseif (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 129) then
								if (Enum <= 127) then
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
								elseif (Enum > 128) then
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
								end
							elseif (Enum <= 130) then
								local A = Inst[2];
								local B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Stk[Inst[4]]];
							elseif (Enum > 131) then
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
						elseif (Enum <= 138) then
							if (Enum <= 135) then
								if (Enum <= 133) then
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Top));
								elseif (Enum > 134) then
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
									Env[Inst[3]] = Stk[Inst[2]];
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
								end
							elseif (Enum <= 136) then
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
							elseif (Enum == 137) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
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
						elseif (Enum <= 141) then
							if (Enum <= 139) then
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
							elseif (Enum > 140) then
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
						elseif (Enum <= 143) then
							if (Enum > 142) then
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
						elseif (Enum > 144) then
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
						else
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
						end
					elseif (Enum <= 169) then
						if (Enum <= 157) then
							if (Enum <= 151) then
								if (Enum <= 148) then
									if (Enum <= 146) then
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
									elseif (Enum == 147) then
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
									end
								elseif (Enum <= 149) then
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
								elseif (Enum == 150) then
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
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
							elseif (Enum <= 154) then
								if (Enum <= 152) then
									Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
								elseif (Enum > 153) then
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
							elseif (Enum <= 155) then
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
							elseif (Enum == 156) then
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
						elseif (Enum <= 163) then
							if (Enum <= 160) then
								if (Enum <= 158) then
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
								elseif (Enum > 159) then
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
								else
									Env[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum <= 161) then
								local A;
								A = Inst[2];
								Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
							elseif (Enum == 162) then
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
						elseif (Enum <= 166) then
							if (Enum <= 164) then
								Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
							elseif (Enum == 165) then
								local A = Inst[2];
								local T = Stk[A];
								local B = Inst[3];
								for Idx = 1, B do
									T[Idx] = Stk[A + Idx];
								end
							else
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
								do
									return;
								end
							end
						elseif (Enum <= 167) then
							Stk[Inst[2]] = #Stk[Inst[3]];
						elseif (Enum > 168) then
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Top));
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
					elseif (Enum <= 181) then
						if (Enum <= 175) then
							if (Enum <= 172) then
								if (Enum <= 170) then
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
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
								elseif (Enum == 171) then
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
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								end
							elseif (Enum <= 173) then
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
								Stk[Inst[2]] = Env[Inst[3]];
							elseif (Enum == 174) then
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
							else
								Stk[Inst[2]] = {};
							end
						elseif (Enum <= 178) then
							if (Enum <= 176) then
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
							elseif (Enum == 177) then
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
							end
						elseif (Enum <= 179) then
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
						elseif (Enum == 180) then
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
					elseif (Enum <= 187) then
						if (Enum <= 184) then
							if (Enum <= 182) then
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
							elseif (Enum == 183) then
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
						elseif (Enum <= 185) then
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
						elseif (Enum == 186) then
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
							Stk[Inst[2]] = Env[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3] ~= 0;
						end
					elseif (Enum <= 190) then
						if (Enum <= 188) then
							local A = Inst[2];
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
						elseif (Enum > 189) then
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
						end
					elseif (Enum <= 192) then
						if (Enum == 191) then
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
					elseif (Enum > 193) then
						if (Stk[Inst[2]] > Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = VIP + Inst[3];
						end
					else
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
					end
				elseif (Enum <= 291) then
					if (Enum <= 242) then
						if (Enum <= 218) then
							if (Enum <= 206) then
								if (Enum <= 200) then
									if (Enum <= 197) then
										if (Enum <= 195) then
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
										elseif (Enum > 196) then
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
										end
									elseif (Enum <= 198) then
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
									elseif (Enum > 199) then
										local B;
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
										Stk[Inst[2]][Inst[3]] = Inst[4];
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
									else
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
									end
								elseif (Enum <= 203) then
									if (Enum <= 201) then
										Upvalues[Inst[3]] = Stk[Inst[2]];
									elseif (Enum == 202) then
										if (Stk[Inst[2]] <= Stk[Inst[4]]) then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
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
								elseif (Enum <= 204) then
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
								elseif (Enum > 205) then
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
							elseif (Enum <= 212) then
								if (Enum <= 209) then
									if (Enum <= 207) then
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
									elseif (Enum > 208) then
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
									end
								elseif (Enum <= 210) then
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
								elseif (Enum > 211) then
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
								else
									Stk[Inst[2]] = Inst[3] ~= 0;
								end
							elseif (Enum <= 215) then
								if (Enum <= 213) then
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
								elseif (Enum == 214) then
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
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								end
							elseif (Enum <= 216) then
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							elseif (Enum == 217) then
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
							else
								Stk[Inst[2]] = Stk[Inst[3]] / Inst[4];
							end
						elseif (Enum <= 230) then
							if (Enum <= 224) then
								if (Enum <= 221) then
									if (Enum <= 219) then
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
									elseif (Enum > 220) then
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
										local A = Inst[2];
										do
											return Unpack(Stk, A, A + Inst[3]);
										end
									end
								elseif (Enum <= 222) then
									local Step;
									local Index;
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
									VIP = VIP + 1;
									Inst = Instr[VIP];
									A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
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
								elseif (Enum > 223) then
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
							elseif (Enum <= 227) then
								if (Enum <= 225) then
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
								elseif (Enum == 226) then
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
								end
							elseif (Enum <= 228) then
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
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							elseif (Enum > 229) then
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
						elseif (Enum <= 236) then
							if (Enum <= 233) then
								if (Enum <= 231) then
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
								elseif (Enum > 232) then
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
							elseif (Enum <= 234) then
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
							elseif (Enum == 235) then
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
							end
						elseif (Enum <= 239) then
							if (Enum <= 237) then
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
							elseif (Enum == 238) then
								local A = Inst[2];
								local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
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
							end
						elseif (Enum <= 240) then
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
						elseif (Enum > 241) then
							if not Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A = Inst[2];
							local T = Stk[A];
							for Idx = A + 1, Inst[3] do
								Insert(T, Stk[Idx]);
							end
						end
					elseif (Enum <= 266) then
						if (Enum <= 254) then
							if (Enum <= 248) then
								if (Enum <= 245) then
									if (Enum <= 243) then
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
									elseif (Enum > 244) then
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
								elseif (Enum <= 246) then
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
								elseif (Enum == 247) then
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
								else
									local B = Inst[3];
									local K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
								end
							elseif (Enum <= 251) then
								if (Enum <= 249) then
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
								elseif (Enum > 250) then
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
								end
							elseif (Enum <= 252) then
								local A = Inst[2];
								local Results = {Stk[A](Stk[A + 1])};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum == 253) then
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
						elseif (Enum <= 260) then
							if (Enum <= 257) then
								if (Enum <= 255) then
									do
										return Stk[Inst[2]];
									end
								elseif (Enum > 256) then
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
								else
									Stk[Inst[2]]();
								end
							elseif (Enum <= 258) then
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
							elseif (Enum > 259) then
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
						elseif (Enum <= 263) then
							if (Enum <= 261) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Top)));
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum > 262) then
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
						elseif (Enum <= 264) then
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						elseif (Enum == 265) then
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
						else
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
						end
					elseif (Enum <= 278) then
						if (Enum <= 272) then
							if (Enum <= 269) then
								if (Enum <= 267) then
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
								elseif (Enum == 268) then
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
							elseif (Enum <= 270) then
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
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							elseif (Enum > 271) then
								local A = Inst[2];
								do
									return Unpack(Stk, A, Top);
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
						elseif (Enum <= 275) then
							if (Enum <= 273) then
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
							elseif (Enum > 274) then
								Stk[Inst[2]] = Stk[Inst[3]] % Inst[4];
							else
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
							end
						elseif (Enum <= 276) then
							local B = Stk[Inst[4]];
							if not B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						elseif (Enum == 277) then
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
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
						end
					elseif (Enum <= 284) then
						if (Enum <= 281) then
							if (Enum <= 279) then
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
							elseif (Enum > 280) then
								Stk[Inst[2]][Inst[3]] = Inst[4];
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
						elseif (Enum <= 282) then
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						elseif (Enum > 283) then
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
						else
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
						end
					elseif (Enum <= 287) then
						if (Enum <= 285) then
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
						elseif (Enum > 286) then
							if (Stk[Inst[2]] < Stk[Inst[4]]) then
								VIP = Inst[3];
							else
								VIP = VIP + 1;
							end
						elseif Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 289) then
						if (Enum > 288) then
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
						else
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
						end
					elseif (Enum > 290) then
						local A = Inst[2];
						Stk[A] = Stk[A]();
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
						if Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					end
				elseif (Enum <= 340) then
					if (Enum <= 315) then
						if (Enum <= 303) then
							if (Enum <= 297) then
								if (Enum <= 294) then
									if (Enum <= 292) then
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
									elseif (Enum > 293) then
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
								elseif (Enum <= 295) then
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
								elseif (Enum > 296) then
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
							elseif (Enum <= 300) then
								if (Enum <= 298) then
									if (Inst[2] <= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 299) then
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
									do
										return;
									end
								end
							elseif (Enum <= 301) then
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
							elseif (Enum > 302) then
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
							end
						elseif (Enum <= 309) then
							if (Enum <= 306) then
								if (Enum <= 304) then
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
								elseif (Enum > 305) then
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
								end
							elseif (Enum <= 307) then
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
							elseif (Enum == 308) then
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
						elseif (Enum <= 312) then
							if (Enum <= 310) then
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
							elseif (Enum == 311) then
								VIP = Inst[3];
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
						elseif (Enum <= 313) then
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 314) then
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
						end
					elseif (Enum <= 327) then
						if (Enum <= 321) then
							if (Enum <= 318) then
								if (Enum <= 316) then
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]]();
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
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								elseif (Enum > 317) then
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
								end
							elseif (Enum <= 319) then
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							elseif (Enum > 320) then
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
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						elseif (Enum <= 324) then
							if (Enum <= 322) then
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
							elseif (Enum > 323) then
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
						elseif (Enum <= 325) then
							Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
						elseif (Enum == 326) then
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
						end
					elseif (Enum <= 333) then
						if (Enum <= 330) then
							if (Enum <= 328) then
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
							elseif (Enum > 329) then
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
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							else
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
							end
						elseif (Enum <= 331) then
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
						elseif (Enum > 332) then
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
							Stk[Inst[2]][Inst[3]] = Inst[4];
						end
					elseif (Enum <= 336) then
						if (Enum <= 334) then
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
						elseif (Enum == 335) then
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
							Stk[Inst[2]][Inst[3]] = Inst[4];
						end
					elseif (Enum <= 338) then
						if (Enum == 337) then
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
						end
					elseif (Enum > 339) then
						Stk[Inst[2]] = not Stk[Inst[3]];
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
				elseif (Enum <= 364) then
					if (Enum <= 352) then
						if (Enum <= 346) then
							if (Enum <= 343) then
								if (Enum <= 341) then
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
									Stk[Inst[2]] = Env[Inst[3]];
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
									Stk[Inst[2]] = Env[Inst[3]];
								elseif (Enum == 342) then
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
								end
							elseif (Enum <= 344) then
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
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							elseif (Enum == 345) then
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
							else
								local B;
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
								A = Inst[2];
								B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							end
						elseif (Enum <= 349) then
							if (Enum <= 347) then
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
							elseif (Enum == 348) then
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
						elseif (Enum <= 350) then
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
						elseif (Enum > 351) then
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
						else
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
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum <= 358) then
						if (Enum <= 355) then
							if (Enum <= 353) then
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
								Stk[Inst[2]] = Inst[3];
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
							elseif (Enum == 354) then
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
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
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
						elseif (Enum <= 356) then
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
						elseif (Enum > 357) then
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
						else
							do
								return Stk[Inst[2]]();
							end
						end
					elseif (Enum <= 361) then
						if (Enum <= 359) then
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
						elseif (Enum > 360) then
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
						end
					elseif (Enum <= 362) then
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
					elseif (Enum == 363) then
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
				elseif (Enum <= 376) then
					if (Enum <= 370) then
						if (Enum <= 367) then
							if (Enum <= 365) then
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
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Env[Inst[3]];
							elseif (Enum > 366) then
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
							end
						elseif (Enum <= 368) then
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
						elseif (Enum == 369) then
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
						end
					elseif (Enum <= 373) then
						if (Enum <= 371) then
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
							Stk[Inst[2]] = Env[Inst[3]];
						elseif (Enum == 372) then
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
								if (Mvm[1] == 388) then
									Indexes[Idx - 1] = {Stk,Mvm[3]};
								else
									Indexes[Idx - 1] = {Upvalues,Mvm[3]};
								end
								Lupvals[#Lupvals + 1] = Indexes;
							end
							Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
						end
					elseif (Enum <= 374) then
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
					elseif (Enum > 375) then
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
				elseif (Enum <= 382) then
					if (Enum <= 379) then
						if (Enum <= 377) then
							if (Inst[2] < Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 378) then
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
						end
					elseif (Enum <= 380) then
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
					elseif (Enum > 381) then
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
				elseif (Enum <= 385) then
					if (Enum <= 383) then
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
					elseif (Enum == 384) then
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
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
					end
				elseif (Enum <= 387) then
					if (Enum > 386) then
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
				elseif (Enum > 388) then
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
				else
					Stk[Inst[2]] = Stk[Inst[3]];
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!6E012Q00030C3Q005343524950545F5449544C45030C3Q00F09F94B04D4158492048554203083Q004755495F4E414D4503073Q004D617869487562030D3Q0054454C454752414D5F4C494E4B03153Q00682Q7470733A2Q2F742E6D652F4D4158495F48554203073Q00506C617965727303043Q0067616D65030A3Q0047657453657276696365030A3Q0052756E5365727669636503103Q0055736572496E70757453657276696365030A3Q0047756953657276696365030B3Q00482Q747053657276696365030C3Q0054772Q656E5365727669636503113Q005265706C69636174656453746F72616765030B3Q00434F4E4649475F46494C4503143Q006D6178692D6875622D636F6E6669672E6A736F6E030F3Q0053452Q4C5F53544154455F46494C4503183Q006D6178692D6875622D73652Q6C2D73746174652E6A736F6E030B3Q004B45595F574542482Q4F4B03793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D6803133Q00444953434F52445F434F4E4649475F46494C4503153Q006D6178692D6875622D646973636F72642E6A736F6E03123Q0055736572446973636F7264576562682Q6F6B034Q0003153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E75746573026Q00244003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F7003063Q00706C6179657203093Q00706C6179657247756903043Q0067656E7603063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47030C3Q00656E73757265506C61796572030B3Q004661726D456E61626C6564030A3Q006661726D54687265616403093Q006661726D52756E4964028Q00030D3Q006661726D54696D65546F74616C030F3Q006661726D54696D655374617274656403123Q0074656C65706F7274436F2Q6E656374696F6E03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503093Q006661726D506861736503043Q0069646C65030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403063Q00484F544B455903043Q00456E756D03073Q004B6579436F64652Q033Q00456E64030F3Q0070656E64696E675072657653746F70030B3Q004D61786948756253746F70030E3Q006661726D436865636B506175736503123Q0073686F756C644661726D436F6E74696E7565030D3Q00697343616E63656C452Q726F7203103Q0063616D657261436F2Q6E656374696F6E030E3Q00612Q706C79496E7669736963616D030E3Q0073746F7043616D6572614C2Q6F70030D3Q00726573746F726543616D657261030F3Q00737461727443616D6572614C2Q6F70030E3Q00434F2Q4C4543545F524144495553026Q004E40030E3Q0054656C65706F7274486569676874027Q004003133Q0053746F6E6554656C65706F7274486569676874026Q000C40030C3Q0069676E6F72656444726F7073030F3Q0063616368656444726F70436F756E7403043Q00564B5F46025Q0080514003073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D417454617267657403113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A65026Q00494003113Q00426C6F636B65645A6F6E6543656E74657203153Q00626C6F636B65645A6F6E6556697375616C5061727403133Q00424C4F434B45445F5A4F4E455F464F4C444552030C3Q004D6178694875625A6F6E6573030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C026Q003440030F3Q0053652Q6C4261746368416D6F756E74025Q004CCD4003143Q0053652Q6C436F636F6E75745468726573686F6C64024Q008093C140030D3Q0053452Q4C5F574F524C445F4944022Q008081CBE4E941030D3Q004641524D5F574F524C445F4944022Q00105C7A23F24103123Q0053452Q4C5F574149545F41465445525F5450026Q001440030A3Q0053452Q4C5F4954454D5303073Q004176616361646F03073Q00436F636F6E757403093Q00436163616F4265616E03053Q00412Q706C6503043Q00436F726E03053Q004C656D6F6E03113Q0073652Q73696F6E53746F6E6544726F707303113Q0073652Q73696F6E54722Q65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E6564030C3Q006661726D5761726E696E6773030D3Q006C6173745761726E696E67417403103Q0073652Q73696F6E54722Q6544726F7073030D3Q004F726269744469616D65746572026Q002C40030A3Q004F7262697453702Q6564029A5Q99F13F030E3Q0044454641554C545F55495F504F5303053Q005544696D322Q033Q006E6577026Q003040026Q00E03F025Q00E070C0030A3Q0073617665645569506F73030C3Q007363722Q656E477569526566030A3Q0068692Q64656E4775697303133Q00736166654D6F6465436F2Q6E656374696F6E73030B3Q0054524144455F48494E545303053Q00747261646503073Q0074726164696E67030A3Q0074726164656F2Q666572030C3Q0074726164657265717565737403083Q0065786368616E676503043Q0073776170030A3Q006F72626974416E676C6503093Q006D6F75736548656C64030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F7573655903103Q0063616E557365436F6E66696746696C6503133Q0073617665436F6E6669675363686564756C6564030C3Q006D61696E4672616D65526566030A3Q0073617665436F6E66696703123Q007363686564756C6553617665436F6E666967030D3Q006C6F616453652Q6C537461746503133Q0068617350656E64696E6753652Q6C5374617465030D3Q007361766553652Q6C5374617465030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F6703123Q0066696E616C697A6553652Q6C526573756D6503103Q006578656375746553652Q6C4974656D73031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F747374726170030A3Q006C6F6164436F6E666967030F3Q00707573684661726D5761726E696E6703103Q00636C6561724661726D5761726E696E6703133Q006765744661726D5761726E696E67735465787403183Q0067657454656C65706F7274486569676874466F724B696E64030F3Q006765744661726D4D6F646554657874030F3Q00535455434B5F465F5345434F4E4453026Q001040030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365030B3Q00736561726368416E676C65030C3Q00736561726368526164697573026Q005440030C3Q00706174726F6C506F696E7473030B3Q00706174726F6C496E646578026Q00F03F030B3Q00687562506F736974696F6E030C3Q004855425F574149545F4D494E026Q000840030C3Q004855425F574149545F4D4158026Q002040030F3Q004855425F4E4541525F524144495553026Q002E40030F3Q006C61737453652Q6C436865636B4174030E3Q0073652Q6C496E50726F6772652Q73030F3Q006D616E75616C53652Q6C546F6B656E03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006765744661726D446973636F7264576562682Q6F6B03113Q0073617665446973636F7264436F6E666967030A3Q0050484153455F5445585403103Q00D0BED0B6D0B8D0B4D0B0D0BDD0B8D0B503063Q00736561726368030A3Q00D0BFD0BED0B8D181D0BA03043Q006D696E65030C3Q00D0B4D0BED0B1D18BD187D0B003043Q007761697403133Q00D0B6D0B4D191D0BC20D0B4D180D0BED0BFD18B03073Q00636F2Q6C65637403083Q00D181D0B1D0BED18003043Q0073652Q6C030E3Q00D0BFD180D0BED0B4D0B0D0B6D0B02Q033Q00687562030A3Q00D186D0B5D0BDD182D18003143Q0067657454656C65706F7274537061776E5061727403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C030B3Q0072656C65617365464B657903103Q0072656C656173654D6F757365486F6C6403133Q0073746F704368617261637465724D6F74696F6E03163Q00676574426C6F636B65645A6F6E6548616C6653697A6503143Q00676574426C6F636B65645A6F6E654D696E4D617803123Q006973506F73496E426C6F636B65645A6F6E6503133Q0069734E6F6465496E426C6F636B65645A6F6E6503173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00757064617465426C6F636B65645A6F6E6556697375616C03163Q00736574426C6F636B65645A6F6E654174506C61796572030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C655761697403183Q00696E74652Q7275707469626C6557616974466F7253652Q6C03123Q0063617074757265487562506F736974696F6E030E3Q00676574487562506F736974696F6E03093Q0069734E656172487562030D3Q0074656C65706F7274546F487562030B3Q00687562526573745761697403143Q0072657475726E546F48756241667465724E6F6465030C3Q0073686F756C645072652Q734603063Q007072652Q7346030B3Q00686F6C644D6F757365417403073Q00636C69636B4174030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73030F3Q0067657450617274506F736974696F6E030F3Q0067657441696D5363722Q656E506F73030B3Q0069734E6F6465416C697665030D3Q006765744E6F64654865616C7468030A3Q0072657365744175746F46030B3Q007570646174654175746F46030B3Q00676574486974626F786573030E3Q00676574436F2Q6C65637450617274030D3Q006765744E6F646543656E746572030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473030E3Q007069636B4265737454617267657403133Q0072656275696C64506174726F6C506F696E7473030E3Q0074656C65706F727453656172636803103Q0044524F505F4D4F44454C5F48494E545303093Q00462Q6F644D6F64656C03123Q00572Q6F645265736F75726365734D6F64656C03143Q00436F2Q7065725265736F75726365734D6F64656C03123Q004C6561665265736F75726365734D6F64656C030E3Q005265736F75726365734D6F64656C03133Q0069735265736F7572636544726F704D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C030D3Q00697344726F7049676E6F72656403113Q006D61726B44726F70436F2Q6C656374656403123Q00697356616C6964436F2Q6C65637444726F7003173Q0066696E6443616D6572615265736F7572636544726F7073030D3Q0066696E6444726F70734E656172030B3Q00636F2Q6C65637450617274030F3Q00636F2Q6C656374412Q6C44726F7073030A3Q00612Q7461636B50617274030F3Q0064726F707341726553652Q746C656403103Q0077616974416E645363616E44726F707303103Q006765744D696E65416E63686F72506F7303103Q0074656C65706F7274546F54617267657403083Q0069734F7572477569030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A656374030A3Q007363616E547261646573030D3Q00686964654F7468657247756973030A3Q00636C6561725461626C65030C3Q0073746F70536166654D6F6465030D3Q007374617274536166654D6F646503123Q006765745265736F7572636573466F6C64657203113Q006765745265736F75726365416D6F756E7403143Q0067657453652Q6C5472692Q676572416D6F756E74030D3Q006E2Q6564734175746F53652Q6C030E3Q006765744661726D5365636F6E6473030B3Q00682Q74705265717565737403123Q00706F7374446973636F7264576562682Q6F6B03103Q0073656E64446973636F7264456D62656403173Q006765745265736F75726365734F7665724F6E655465787403153Q0067657453652Q73696F6E53746174734669656C647303153Q006C6F674661726D53652Q73696F6E446973636F726403133Q0077616974466F7243686172616374657248727003083Q0073652Q6C57616974030D3Q0067657453652Q6C52656D6F746503163Q00676574576F726C6454656C65706F727452656D6F7465030D3Q00776F726C6454656C65706F727403103Q0073652Q6C5265736F757263654974656D030C3Q0072756E53652Q6C4379636C65030B3Q0072756E4175746F53652Q6C030D3Q0072756E4D616E75616C53652Q6C03103Q006D6179626552756E4175746F53652Q6C03123Q006D6179626552756E4661726D5265706F7274030E3Q0072756E5365617263685068617365030D3Q006B692Q6C4661726D4C2Q6F707303083Q0073746F704661726D030B3Q00736F6674436C65616E7570030A3Q0066752Q6C556E6C6F616403093Q0073746172744661726D030F3Q004D617869487562476574537461747303183Q004D6178694875625061757365466F72496E76656E746F7279031B3Q004D617869487562526573756D654166746572496E76656E746F727903113Q005F4D61786948756255494C69627261727903123Q004D6178694875624F2Q66696369616C52617703113Q004D61786948756252656D6F746542617365030F3Q004D6178694875625265706F4F6E6C7903073Q00482Q747047657403043Q007479706503063Q00737472696E6703053Q00652Q726F72033F3Q005B4D415849204855425D20554920D182D0BED0BBD18CD0BAD0BE20D18120D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD0BED0B3D0BE20D180D0B5D0BFD0BE03083Q007265616466696C6503063Q00697366696C6503063Q0069706169727303183Q006D6178692D6875622F6D6178692D6875622D75692E6C7561030F3Q006D6178692D6875622D75692E6C756103583Q005B4D415849204855425D20D09DD183D0B6D0B5D0BD206D6178692D6875622D75692E6C75612028D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD18BD0B920D180D0B5D0BFD0BE20D0B8D0BBD0B820776F726B737061636529030A3Q006C6F6164737472696E6703103Q00406D6178692D6875622D75692E6C756103173Q005B4D415849204855425D20554920636F6D70696C653A2003083Q00746F737472696E6703133Q005B4D415849204855425D2055492072756E3A20030C3Q004D61786948756255494C696203093Q0055495F4C41594F555403073Q0050414E454C5F57026Q00694003073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58026Q006B4003063Q00524F57335F59026Q006C4003063Q0046552Q4C5F57025Q00407A40030E3Q00534C494445525F50414E454C5F48026Q006440030E3Q0053452Q53494F4E5F424F44595F59025Q00804140030D3Q00534C494445525F424F44595F59026Q004440030A3Q004D494E455F424F585F48025Q00C06540030D3Q00534C49444552535F424F585F48026Q005C40030A3Q00534146455F424F585F48026Q005640030D3Q00544F2Q474C455F595F53544550026Q004640030D3Q00534C494445525F595F5354455003163Q006275696C644D61786948756243726564697473546162030F3Q00687562422Q6F74737472612Q70656403103Q00622Q6F7473747261704D617869487562030D3Q006C61756E63684D617869487562030F3Q004D61786948756252656C61756E636803083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C6179657247756903053Q007072696E7403283Q005B4D415849204855425D20D0BCD0BED0B4D183D0BBD18C20D0B7D0B0D0B3D180D183D0B6D0B5D0BD03043Q007461736B03053Q006465666572001A032Q0012813Q00023Q00124Q00013Q00124Q00043Q00124Q00033Q00124Q00063Q00124Q00053Q00124Q00083Q00206Q000900122Q000200078Q0002000200129F3Q00073Q0012FB3Q00083Q00206Q000900122Q0002000A8Q0002000200124Q000A3Q00124Q00083Q00206Q000900122Q0002000B8Q0002000200124Q000B3Q0012FB3Q00083Q00206Q000900122Q0002000C8Q0002000200124Q000C3Q00124Q00083Q00206Q000900122Q0002000D8Q0002000200124Q000D3Q0012FB3Q00083Q00206Q000900122Q0002000E8Q0002000200124Q000E3Q00124Q00083Q00206Q000900122Q0002000F8Q0002000200124Q000F3Q0012433Q00113Q00129F3Q00103Q0012433Q00133Q0012523Q00123Q00124Q00153Q00124Q00143Q00124Q00173Q00124Q00163Q00124Q00193Q00124Q00188Q00013Q00124Q001A3Q00124Q001C3Q00129F3Q001B4Q0060012Q00013Q00124Q001D8Q00013Q00124Q001E9Q003Q00124Q001F9Q003Q00124Q00209Q003Q00124Q00213Q0012EB3Q00223Q0012EB000100234Q00063Q00020002002639012Q004A00010024000437012Q004A00010012EB3Q00234Q0023012Q0001000200129F3Q00213Q000437012Q004C00010012EB3Q00253Q00129F3Q00213Q0002727Q0012EF3Q00269Q003Q00124Q00279Q003Q00124Q00283Q0012433Q002A3Q00129F3Q00293Q0012433Q002A3Q00129F3Q002B3Q0012433Q002A3Q00129F3Q002C4Q00127Q00124Q002D9Q003Q00124Q002E9Q003Q00124Q002F3Q00124Q00313Q00124Q00303Q00124Q00333Q00124Q00323Q0012433Q002A3Q0012863Q00343Q00124Q002A3Q00124Q00353Q00124Q00373Q00206Q003800206Q003900124Q00369Q003Q00124Q003A3Q00124Q00223Q0012EB000100213Q0020082Q010001003B2Q00063Q00020002002639012Q007500010024000437012Q007500010012EB3Q00213Q002008014Q003B00129F3Q003A4Q00D37Q00129F3Q003C3Q0002723Q00013Q00129F3Q003D3Q0002723Q00023Q00129F3Q003E4Q00AE7Q00129F3Q003F3Q0002723Q00033Q00129F3Q00403Q0002723Q00043Q00129F3Q00413Q0002723Q00053Q00129F3Q00423Q0002723Q00063Q001257012Q00433Q00124Q00453Q00124Q00443Q00124Q00473Q00124Q00463Q00124Q00493Q00124Q00489Q003Q00124Q004A3Q00124Q002A3Q00124Q004B3Q00124Q004D3Q00124Q004C8Q00013Q00124Q004E8Q00013Q00124Q004F9Q003Q00124Q00508Q00013Q00124Q00518Q00013Q00124Q00528Q00013Q00124Q00538Q00013Q00124Q00549Q003Q00124Q00559Q003Q00124Q00569Q003Q00124Q00573Q00124Q00593Q00124Q00589Q003Q00124Q005A9Q003Q00124Q005B3Q00124Q005D3Q00124Q005C8Q00013Q00124Q005E3Q00124Q00603Q00124Q005F3Q00124Q00623Q00124Q00613Q00124Q00643Q00124Q00633Q00124Q00663Q00124Q00653Q00124Q00683Q00124Q00673Q00124Q006A3Q00124Q00698Q00063Q00122Q0001006C3Q00122Q0002006D3Q00122Q0003006E3Q00122Q0004006F3Q00122Q000500703Q00122Q000600718Q0006000100129F3Q006B3Q0012283Q002A3Q00124Q00723Q00124Q002A3Q00124Q00733Q00124Q002A3Q00124Q00749Q003Q00124Q00759Q003Q00124Q00763Q0012433Q002A3Q001227012Q00773Q00124Q00793Q00124Q00783Q00124Q007B3Q00124Q007A3Q00124Q007D3Q00206Q007E00122Q0001002A3Q00122Q0002007F3Q00122Q000300803Q001243000400814Q00903Q0004000200124Q007C9Q003Q00124Q00829Q003Q00124Q00839Q003Q00124Q00849Q003Q00124Q00854Q00AF3Q00063Q0012D5000100873Q00122Q000200883Q00122Q000300893Q00122Q0004008A3Q00122Q0005008B3Q00122Q0006008C8Q0006000100129F3Q00863Q001236012Q002A3Q00124Q008D9Q003Q00124Q008E3Q00124Q002A3Q00122Q0001002A3Q00122Q000100903Q00124Q008F3Q0002723Q00073Q0012EF3Q00919Q003Q00124Q00929Q003Q00124Q00933Q0002723Q00083Q00129F3Q00943Q0002723Q00093Q00129F3Q00953Q0002723Q000A3Q00129F3Q00963Q0002723Q000B3Q00129F3Q00973Q0002723Q000C3Q00129F3Q00983Q0002723Q000D3Q00129F3Q00993Q0002723Q000E3Q00129F3Q009A3Q0002723Q000F3Q00129F3Q009B3Q0002723Q00103Q00129F3Q009C3Q0002723Q00113Q00129F3Q009D3Q0002723Q00123Q00129F3Q009E3Q0002723Q00133Q00129F3Q009F3Q0002723Q00143Q00129F3Q00A03Q0002723Q00153Q00129F3Q00A13Q0002723Q00163Q00129F3Q00A23Q0002723Q00173Q0012E33Q00A33Q00124Q00A53Q00124Q00A49Q003Q00124Q00A69Q003Q00124Q00A73Q00124Q002A3Q00124Q00A83Q00124Q002A3Q00129F3Q00A93Q0012D43Q00AB3Q00124Q00AA9Q003Q00124Q00AC3Q00124Q00AE3Q00124Q00AD9Q003Q00124Q00AF3Q00124Q00B13Q00124Q00B03Q0012433Q00B33Q0012BD3Q00B23Q00124Q00B53Q00124Q00B43Q00124Q002A3Q00124Q00B69Q003Q00124Q00B73Q00124Q002A3Q00124Q00B83Q00124Q002A3Q00129F3Q00B93Q0012EB3Q001B3Q0020A45Q004500129F3Q00BA3Q0002723Q00183Q00129F3Q00BB3Q0002723Q00193Q0012783Q00BC9Q00000700304Q003300BE00304Q00BF00C000304Q00C100C200304Q00C300C400304Q00C500C600304Q00C700C800304Q00C900CA00124Q00BD3Q0002723Q001A3Q00129F3Q00CB4Q00AE7Q00129F3Q00CC3Q0012EB3Q00CD3Q0002720001001B4Q00313Q000200010002723Q001C3Q00129F3Q00CE3Q0002723Q001D3Q00129F3Q00CF3Q0002723Q001E3Q00129F3Q00D03Q0002723Q001F3Q00129F3Q00D13Q0002723Q00203Q00129F3Q00D23Q0002723Q00213Q00129F3Q00D33Q0002723Q00223Q00129F3Q00D43Q0002723Q00233Q00129F3Q00D53Q0002723Q00243Q00129F3Q00D63Q0002723Q00253Q00129F3Q00D73Q0002723Q00263Q00129F3Q00D83Q0002723Q00273Q00129F3Q00D93Q0002723Q00283Q00129F3Q00DA3Q0002723Q00293Q00129F3Q00DB3Q0002723Q002A3Q00129F3Q00DC3Q0002723Q002B3Q00129F3Q00DD3Q0002723Q002C3Q00129F3Q00DE3Q0002723Q002D3Q00129F3Q00DF3Q0002723Q002E3Q00129F3Q00E03Q0002723Q002F3Q00129F3Q00E13Q0002723Q00303Q00129F3Q00E23Q0002723Q00313Q00129F3Q00E33Q0002723Q00323Q00129F3Q00E43Q0002723Q00333Q00129F3Q00E53Q0002723Q00343Q00129F3Q00E63Q0002723Q00353Q00129F3Q00E73Q0002723Q00363Q00129F3Q00E83Q0002723Q00373Q00129F3Q00E93Q0002723Q00383Q00129F3Q00EA3Q0002723Q00393Q00129F3Q00EB3Q0002723Q003A3Q00129F3Q00EC3Q0002723Q003B3Q00129F3Q00ED3Q0002723Q003C3Q00129F3Q00EE3Q0002723Q003D3Q00129F3Q00EF3Q0002723Q003E3Q00129F3Q00F03Q0002723Q003F3Q00129F3Q00F13Q0002723Q00403Q00129F3Q00F23Q0002723Q00413Q00129F3Q00F33Q0002723Q00423Q00129F3Q00F43Q0002723Q00433Q0012423Q00F58Q00053Q00122Q000100F73Q00122Q000200F83Q00122Q000300F93Q00122Q000400FA3Q00122Q000500FB8Q0005000100129F3Q00F63Q0002723Q00443Q00129F3Q00FC3Q0002723Q00453Q00129F3Q00FD3Q0002723Q00463Q00129F3Q00FE3Q0002723Q00473Q00129F3Q00FF3Q0002723Q00483Q00129F4Q00012Q0002723Q00493Q00129F3Q002Q012Q0002723Q004A3Q00129F3Q0002012Q0002723Q004B3Q00129F3Q0003012Q0002723Q004C3Q00129F3Q0004012Q0002723Q004D3Q00129F3Q0005012Q0002723Q004E3Q00129F3Q0006012Q0002723Q004F3Q00129F3Q0007012Q0002723Q00503Q00129F3Q0008012Q0002723Q00513Q00129F3Q0009012Q0002723Q00523Q00129F3Q000A012Q0002723Q00533Q00129F3Q000B012Q0002723Q00543Q00129F3Q000C012Q0002723Q00553Q00129F3Q000D012Q0002723Q00563Q00129F3Q000E012Q0002723Q00573Q00129F3Q000F012Q0002723Q00583Q00129F3Q0010012Q0002723Q00593Q00129F3Q0011012Q0002723Q005A3Q00129F3Q0012012Q0002723Q005B3Q00129F3Q0013012Q0002723Q005C3Q00129F3Q0014012Q0002723Q005D3Q00129F3Q0015012Q0002723Q005E3Q00129F3Q0016012Q0002723Q005F3Q00129F3Q0017012Q0002723Q00603Q00129F3Q0018012Q0002723Q00613Q00129F3Q0019012Q0002723Q00623Q00129F3Q001A012Q0002723Q00633Q00129F3Q001B012Q0002723Q00643Q00129F3Q001C012Q0002723Q00653Q00129F3Q001D012Q0002723Q00663Q00129F3Q001E012Q0002723Q00673Q00129F3Q001F012Q0002723Q00683Q00129F3Q0020012Q0002723Q00693Q00129F3Q0021012Q0002723Q006A3Q00129F3Q0022012Q0002723Q006B3Q00129F3Q0023012Q0002723Q006C3Q00129F3Q0024012Q0002723Q006D3Q00129F3Q0025012Q0002723Q006E3Q00129F3Q0026012Q0002723Q006F3Q00129F3Q0027012Q0002723Q00703Q00129F3Q0028012Q0002723Q00713Q00129F3Q0029012Q0002723Q00723Q00129F3Q002A012Q0002723Q00733Q00129F3Q002B012Q0002723Q00743Q0012743Q002C012Q00124Q00213Q00122Q0001002B012Q00104Q003B000100124Q003A3Q00064Q001902013Q000437012Q001902010012EB3Q003A3Q0012EB0001002B012Q00062A3Q001902010001000437012Q001902010012EB3Q00CD3Q0012EB0001003A4Q00313Q000200012Q00AE7Q00129F3Q003A3Q0002723Q00753Q00129F3Q002D012Q0012EB3Q00213Q0012430001002E012Q000272000200764Q0045012Q000100020012EB3Q00213Q0012430001002F012Q000272000200774Q0045012Q000100020012EB3Q00213Q00124300010030012Q000272000200784Q0077012Q0001000200124Q00223Q00122Q000100238Q0002000200264Q003202010024000437012Q003202010012EB3Q00234Q0023012Q000100020006F23Q003302010001000437012Q003302010012EB3Q00253Q00124300010031013Q00AC00013Q00010006F2000100AB02010001000437012Q00AB02012Q00AE000100013Q00124300020032013Q00AC00023Q00020006F20002003E02010001000437012Q003E020100124300020033013Q00AC00023Q000200124300030034013Q00AC00033Q00032Q00D3000400013Q00062A0003004402010004000437012Q004402012Q001B00036Q00D3000300013Q00061E0102006902013Q000437012Q006902010012EB000400223Q001257000500083Q00122Q00060035015Q0005000500064Q00040002000200262Q0004006902010024000437012Q00690201000272000400793Q0012EB000500CD3Q0006750106007A000100012Q0084012Q00024Q00FC00050002000600061E0105006902013Q000437012Q006902010012EB00070036013Q0084010800064Q000600070002000200124300080037012Q00067D0007006902010008000437012Q006902010026BF0006006902010019000437012Q006902012Q0084010700044Q0084010800064Q00060007000200020006F20007006402010001000437012Q006402012Q00842Q0100063Q000437012Q0069020100061E0103006902013Q000437012Q006902010012EB00070038012Q00124300080039013Q00310007000200010006F20001008A02010001000437012Q008A02010006F20003008A02010001000437012Q008A02010012EB000400223Q0012EB0005003A013Q00060004000200020026390104008A02010024000437012Q008A02010012EB000400223Q0012EB0005003B013Q00060004000200020026390104008A02010024000437012Q008A02010012EB0004003C013Q00AF000500023Q0012430006003D012Q0012430007003E013Q00A50005000200012Q00FC000400020006000437012Q008802010012EB0009003B013Q0084010A00084Q000600090002000200061E0109008802013Q000437012Q008802010012EB0009003A013Q0084010A00084Q00060009000200022Q00842Q0100093Q000437012Q008A020100067C0104007E02010002000437012Q007E02010006F20001008F02010001000437012Q008F02010012EB00040038012Q0012430005003F013Q00310004000200010012EB00040040013Q0084010500013Q00124300060041013Q001A0104000600050006F20004009C02010001000437012Q009C02010012EB00060038012Q0012C500070042012Q00122Q00080043015Q000900056Q0008000200024Q0007000700084Q0006000200010012EB000600CD4Q0084010700044Q00FC0006000200070006F2000600A802010001000437012Q00A802010012EB00080038012Q0012C500090044012Q00122Q000A0043015Q000B00076Q000A000200024Q00090009000A4Q00080002000100124300080031013Q0045012Q000800072Q00F600015Q0012EB3Q00223Q0012EB000100234Q00063Q00020002002639012Q00B402010024000437012Q00B402010012EB3Q00234Q0023012Q000100020006F23Q00B502010001000437012Q00B502010012EB3Q00253Q00124300010031013Q00B55Q000100124Q0045019Q000D00122Q00010047012Q00122Q00020048017Q0001000200122Q00010049012Q00122Q00020048017Q0001000200122Q0001004A012Q0012170102004B017Q0001000200122Q0001004C012Q00122Q0002004D017Q0001000200122Q0001004E012Q00122Q0002004F017Q0001000200122Q00010050012Q00122Q00020051013Q00093Q0001000200122Q00010052012Q00122Q00020053017Q0001000200122Q00010054012Q00122Q00020055017Q0001000200122Q00010056012Q00122Q00020057017Q0001000200124300010058012Q00121701020059017Q0001000200122Q0001005A012Q00122Q0002005B017Q0001000200122Q0001005C012Q00122Q0002005D017Q0001000200122Q0001005E012Q00122Q000200454Q0045012Q0001000200129F3Q0046012Q0002723Q007B3Q00129F3Q005F013Q00D37Q00129F3Q0060012Q0002723Q007C3Q00129F3Q0061012Q0002723Q007D3Q00129F3Q0062012Q0012EB3Q00213Q00124300010063012Q0002720002007E4Q0045012Q000100020012EB3Q001F3Q00061E012Q00F302013Q000437012Q00F302010012EB3Q00203Q0006F23Q001103010001000437012Q001103010012EB3Q00083Q00124300020064013Q00825Q00022Q00063Q000200020006F23Q00FF02010001000437012Q00FF02010012EB3Q00083Q00122900010065019Q000100122Q00020066019Q00026Q000200010012EB3Q00073Q00124300010067013Q00AC5Q00010006F23Q000A03010001000437012Q000A03010012EB3Q00073Q00123B2Q010068019Q000100122Q00020066019Q00026Q0002000200129F3Q001F3Q0012B93Q001F3Q00122Q00020069019Q000200122Q0002006A017Q0002000200124Q00203Q0012EB3Q006B012Q0012C60001006C017Q0002000100124Q006D012Q00122Q0001006E019Q00010002720001007F4Q00313Q000200012Q00583Q00013Q00803Q00143Q0003063Q00706C6179657203093Q00706C6179657247756903063Q00506172656E7403043Q0067616D6503083Q0049734C6F6164656403063Q004C6F6164656403043Q005761697403073Q00506C6179657273030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030E3Q0046696E6446697273744368696C6403093Q00506C61796572477569030C3Q0057616974466F724368696C64026Q003E40030E3Q004D6178694875624B65794761746503073Q0044657374726F7903043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C0003053Q007063612Q6C00443Q0012EB3Q00013Q00061E012Q000C00013Q000437012Q000C00010012EB3Q00023Q00061E012Q000C00013Q000437012Q000C00010012EB3Q00023Q002008014Q000300061E012Q000C00013Q000437012Q000C00012Q00D33Q00014Q00FF3Q00023Q0012EB3Q00043Q0020BC5Q00052Q00063Q000200020006F23Q001500010001000437012Q001500010012EB3Q00043Q002008014Q00060020BC5Q00072Q00313Q000200010012EB3Q00083Q002008014Q00090006F23Q001E00010001000437012Q001E00010012EB000100083Q0020082Q010001000A0020BC0001000100072Q00060001000200022Q0084012Q00013Q00129F3Q00013Q0012E7000100013Q00202Q00010001000B00122Q0003000C6Q00010003000200122Q000100023Q00122Q000100023Q00062Q0001002D00010001000437012Q002D00010012EB000100013Q00200F2Q010001000D00122Q0003000C3Q00122Q0004000E6Q00010004000200122Q000100023Q0012EB000100023Q0006F20001003200010001000437012Q003200012Q00D300016Q00FF000100023Q0012EB000100023Q0020BC00010001000B0012430003000F4Q003F2Q010003000200061E2Q01003A00013Q000437012Q003A00010020BC0002000100102Q00310002000200010012EB000200113Q0020080102000200120026390102004100010013000437012Q004100010012EB000200143Q00027200036Q00310002000200012Q00D3000200014Q00FF000200024Q00583Q00013Q00013Q00043Q0003043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646500053Q0012E53Q00013Q00122Q000100033Q00202Q00010001000400104Q000200016Q00017Q00033Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964030E3Q006661726D436865636B5061757365010D3Q0012EB000100013Q00061E2Q01000B00013Q000437012Q000B00010012EB000100023Q00067D3Q000900010001000437012Q000900010012EB000100034Q00542Q0100013Q000437012Q000B00012Q001B00016Q00D3000100014Q00FF000100024Q00583Q00017Q00083Q0003063Q00747970656F6603063Q00737472696E6703053Q006C6F77657203043Q0066696E6403063Q0063616E63656C026Q00F03F0003073Q0063616E63652Q6C01213Q0012EB000100014Q008401026Q00060001000200020026BF0001000700010002000437012Q000700012Q00D300016Q00FF000100023Q0012EB000100023Q00204C0001000100034Q00028Q00010002000200122Q000200023Q00202Q0002000200044Q000300013Q00122Q000400053Q00122Q000500066Q000600016Q00020006000200262Q0002001E00010007000437012Q001E00010012EB000200023Q0020080002000200044Q000300013Q00122Q000400083Q00122Q000500066Q000600016Q00020006000200262Q0002001E00010007000437012Q001E00012Q001B00026Q00D3000200014Q00FF000200024Q00583Q00017Q00013Q0003053Q007063612Q6C00043Q0012EB3Q00013Q00027200016Q00313Q000200012Q00583Q00013Q00013Q00043Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q00456E756D03093Q00496E7669736963616D00063Q0012E13Q00013Q00122Q000100033Q00202Q00010001000200202Q00010001000400104Q000200016Q00017Q00023Q0003103Q0063616D657261436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400093Q0012EB3Q00013Q00061E012Q000800013Q000437012Q000800010012EB3Q00013Q0020BC5Q00022Q00313Q000200012Q00AE7Q00129F3Q00014Q00583Q00017Q00023Q00030E3Q0073746F7043616D6572614C2Q6F7003053Q007063612Q6C00063Q0012EB3Q00015Q00012Q000100010012EB3Q00023Q00027200016Q00313Q000200012Q00583Q00013Q00013Q00063Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03043Q00456E756D03043Q005A2Q6F6D000A3Q0012EB3Q00013Q0012EB000100033Q0020082Q01000100040006F20001000800010001000437012Q000800010012EB000100053Q0020082Q01000100020020082Q010001000600101C3Q000200012Q00583Q00017Q00063Q00030E3Q0073746F7043616D6572614C2Q6F70030E3Q00612Q706C79496E7669736963616D03103Q0063616D657261436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374000B3Q0012943Q00018Q0001000100124Q00028Q0001000100124Q00043Q00206Q000500206Q000600122Q000200028Q0002000200124Q00034Q00583Q00017Q00053Q0003063Q00747970656F6603093Q00777269746566696C6503083Q0066756E6374696F6E03083Q007265616466696C6503063Q00697366696C6500133Q0012EB3Q00013Q0012EB000100024Q00063Q00020002002639012Q000F00010003000437012Q000F00010012EB3Q00013Q0012EB000100044Q00063Q00020002002639012Q000F00010003000437012Q000F00010012EB3Q00013Q0012EB000100054Q00063Q000200020026BF3Q001000010003000437012Q001000012Q001B8Q00D33Q00014Q00FF3Q00024Q00583Q00017Q00243Q0003103Q0063616E557365436F6E66696746696C65030E3Q0054656C65706F727448656967687403133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A6503113Q00426C6F636B65645A6F6E6543656E74657203013Q005803013Q005903013Q005A030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F70030C3Q006D61696E4672616D6552656603083Q00506F736974696F6E03083Q005569585363616C6503053Q005363616C6503093Q005569584F2Q6673657403063Q004F2Q6673657403083Q005569595363616C6503093Q005569594F2Q6673657403053Q007063612Q6C005D3Q0012EB3Q00014Q0023012Q000100020006F23Q000500010001000437012Q000500012Q00583Q00014Q00AF5Q0014001213000100023Q00104Q0002000100122Q000100033Q00104Q0003000100122Q000100043Q00104Q0004000100122Q000100053Q00104Q0005000100122Q000100063Q00104Q000600010012EB000100073Q00103E012Q0007000100122Q000100083Q00104Q0008000100122Q000100093Q00104Q000900010012E00001000A3Q00104Q000A000100122Q0001000B3Q00104Q000B000100122Q0001000C3Q00104Q000C000100122Q0001000D3Q00104Q000D000100122Q0001000E3Q00104Q000E000100122Q0001000F3Q00104Q000F000100122Q000100103Q00104Q0010000100122Q000100113Q00062Q0001003100013Q000437012Q003100012Q00AF000100033Q0012DB000200113Q00202Q00020002001200122Q000300113Q00202Q00030003001300122Q000400113Q00202Q0004000400144Q0001000300010006F20001003200010001000437012Q003200012Q00AE000100013Q00101C3Q001100010012E0000100153Q00104Q0015000100122Q000100163Q00104Q0016000100122Q000100173Q00104Q0017000100122Q000100183Q00104Q0018000100122Q000100193Q00104Q0019000100122Q0001001A3Q00104Q001A000100122Q0001001B3Q00104Q001B000100122Q0001001C3Q00062Q0001005200013Q000437012Q005200010012EB0001001C3Q00203700010001001D00202Q00020001001200202Q00020002001F00104Q001E000200202Q00020001001200202Q00020002002100104Q0020000200202Q00020001001300202Q00020002001F00104Q0022000200202Q00020001001300202Q00020002002100104Q002300020012EB000100243Q00067501023Q000100012Q0084017Q00FC00010002000200061E2Q01005C00013Q000437012Q005C00010012EB000300243Q00067501040001000100012Q0084012Q00024Q00310003000200012Q00583Q00013Q00023Q00023Q00030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500063Q001259012Q00013Q00206Q00024Q00029Q0000029Q008Q00017Q00023Q0003093Q00777269746566696C65030B3Q00434F4E4649475F46494C4500053Q0012C73Q00013Q00122Q000100026Q00029Q00000200016Q00017Q00043Q0003133Q0073617665436F6E6669675363686564756C656403043Q007461736B03053Q0064656C6179026Q00D03F000C3Q0012EB3Q00013Q00061E012Q000400013Q000437012Q000400012Q00583Q00014Q00D33Q00013Q00129F3Q00013Q0012EB3Q00023Q002008014Q0003001243000100043Q00027200026Q0040012Q000200012Q00583Q00013Q00013Q00023Q0003133Q0073617665436F6E6669675363686564756C6564030A3Q0073617665436F6E66696700054Q00177Q00124Q00013Q00124Q00028Q000100016Q00017Q00073Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C65030B3Q0070656E64696E6753652Q6C001C3Q0012EB3Q00014Q0023012Q0001000200061E012Q000900013Q000437012Q000900010012EB3Q00023Q0012EB000100034Q00063Q000200020006F23Q000B00010001000437012Q000B00012Q00AE8Q00FF3Q00023Q0012EB3Q00043Q00027200016Q00FC3Q0002000100061E012Q001900013Q000437012Q001900010012EB000200054Q0084010300014Q00060002000200020026390102001900010006000437012Q0019000100200801020001000700061E0102001900013Q000437012Q001900012Q00FF000100024Q00AE000200024Q00FF000200024Q00583Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030F3Q0053452Q4C5F53544154455F46494C4500083Q0012463Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00023Q00030D3Q006C6F616453652Q6C53746174652Q00083Q0012EB3Q00014Q0023012Q00010002002639012Q000500010002000437012Q000500012Q001B8Q00D33Q00014Q00FF3Q00024Q00583Q00017Q00093Q0003103Q0063616E557365436F6E66696746696C65030B3Q0070656E64696E6753652Q6C2Q0103053Q00706861736503063Q006D616E75616C030A3Q00726573756D654661726D03073Q007361766564417403043Q007469636B03053Q007063612Q6C02203Q0006F20001000400010001000437012Q000400012Q00AF00026Q00842Q0100023Q0012EB000200014Q00230102000100020006F20002000900010001000437012Q000900012Q00583Q00014Q00AF00023Q000500301901020002000300101C000200043Q0020080103000100050026BF0003001000010003000437012Q001000012Q001B00036Q00D3000300013Q00101C0002000500030020080103000100060026BF0003001600010003000437012Q001600012Q001B00036Q00D3000300013Q00100C00020006000300122Q000300086Q00030001000200102Q00020007000300122Q000300093Q00067501043Q000100012Q0084012Q00024Q00310003000200012Q00583Q00013Q00013Q00043Q0003093Q00777269746566696C65030F3Q0053452Q4C5F53544154455F46494C45030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500083Q00127A012Q00013Q00122Q000100023Q00122Q000200033Q00202Q0002000200044Q00048Q000200049Q0000016Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503053Q007063612Q6C00093Q0012EB3Q00014Q0023012Q000100020006F23Q000500010001000437012Q000500012Q00583Q00013Q0012EB3Q00023Q00027200016Q00313Q000200012Q00583Q00013Q00013Q00073Q0003063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503093Q00777269746566696C65030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465030B3Q0070656E64696E6753652Q6C012Q000E3Q0012EB3Q00013Q0012EB000100024Q00063Q0002000200061E012Q000D00013Q000437012Q000D00010012EB3Q00033Q00127E2Q0100023Q00122Q000200043Q00202Q0002000200054Q00043Q000100302Q0004000600074Q000200049Q0000012Q00583Q00017Q00013Q0003053Q007063612Q6C01093Q0006F23Q000400010001000437012Q000400012Q00AF00016Q0084012Q00013Q0012EB000100013Q00067501023Q000100012Q0084017Q00310001000200012Q00583Q00013Q00013Q00083Q0003053Q00666F72636503153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003153Q006C6F674661726D53652Q73696F6E446973636F726403213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B0023Q00E081386E4103103Q00446973636F72644C6F674F6E53652Q6C00184Q00387Q002008014Q000100061E012Q001000013Q000437012Q001000010012EB3Q00023Q00061E012Q001700013Q000437012Q001700010012EB3Q00034Q0023012Q000100020026BF3Q001700010004000437012Q001700010012EB3Q00053Q001243000100063Q001243000200074Q0040012Q00020001000437012Q001700010012EB3Q00083Q00061E012Q001700013Q000437012Q001700010012EB3Q00053Q001243000100063Q001243000200074Q0040012Q000200012Q00583Q00017Q00053Q00030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F67030A3Q00726573756D654661726D03043Q007461736B03053Q006465666572020E3Q001270000200016Q00020001000100122Q000200026Q00038Q00020002000100202Q00023Q000300062Q0002000C00013Q000437012Q000C00010012EB000200043Q00200801020002000500027200036Q00310002000200012Q00FF000100024Q00583Q00013Q00013Q00043Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D00113Q0012EB3Q00013Q0006F23Q001000010001000437012Q001000012Q00D33Q00013Q00129F3Q00023Q0012EB3Q00033Q00061E012Q000C00013Q000437012Q000C00010012EB3Q00034Q00D3000100014Q00D3000200014Q0040012Q000200012Q00D37Q00129F3Q00023Q0012EB3Q00045Q00012Q000100012Q00583Q00017Q00063Q0003063Q00697061697273030A3Q0053452Q4C5F4954454D5303103Q0073652Q6C5265736F757263654974656D029A5Q99B93F03043Q007461736B03043Q0077616974022B4Q004401025Q00122Q000300013Q00122Q000400026Q00030002000500044Q0027000100061E2Q01000C00013Q000437012Q000C00012Q0084010800014Q00230108000100020006F20008000C00010001000437012Q000C0001000437012Q002900010012EB000800034Q0084010900074Q000600080002000200061E0108001200013Q000437012Q001200012Q00D3000200013Q0012EB000800024Q00A7000800083Q0006340006001F00010008000437012Q001F000100061E012Q001F00013Q000437012Q001F00012Q008401085Q001243000900044Q00060008000200020006F20008002700010001000437012Q00270001000437012Q00290001000437012Q002700010012EB000800024Q00A7000800083Q0006340006002700010008000437012Q002700010012EB000800053Q002008010800080006001243000900044Q003100080002000100067C0103000500010002000437012Q000500012Q00FF000200024Q00583Q00017Q00033Q00030D3Q006C6F616453652Q6C537461746503043Q007461736B03053Q00737061776E000E3Q0012EB3Q00014Q0023012Q000100020006F23Q000600010001000437012Q000600012Q00D300016Q00FF000100023Q0012EB000100023Q0020082Q010001000300067501023Q000100012Q0084017Q00310001000200012Q00D3000100014Q00FF000100024Q00583Q00013Q00013Q001D3Q00030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0073652Q6C03053Q00666F72636503063Q006D616E75616C2Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303053Q007068617365032A3Q00D092D0BED0B7D0BED0B1D0BDD0BED0B2D0BBD18FD0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E03133Q0077616974466F72436861726163746572487270026Q00284003043Q007461736B03043Q007761697403123Q0053452Q4C5F574149545F41465445525F545003203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D73030D3Q007361766553652Q6C537461746503063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q00776F726C6454656C65706F7274030D3Q004641524D5F574F524C445F4944027Q0040030D3Q006C6F616453652Q6C537461746503123Q0066696E616C697A6553652Q6C526573756D6503243Q00D097D0B0D0B2D0B5D180D188D0B0D0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E026Q00F03F030E3Q00636C65617253652Q6C537461746503043Q0069646C6500673Q0012EB3Q00013Q00061E012Q000400013Q000437012Q000400012Q00583Q00014Q00D33Q00013Q00124B012Q00013Q00124Q00033Q00124Q00029Q0000034Q00015Q00202Q00010001000500262Q0001000E00010006000437012Q000E00012Q001B00016Q00D3000100013Q00101C3Q000400012Q003800015Q0020082Q01000100070026BF0001001500010006000437012Q001500012Q001B00016Q00D3000100013Q00101C3Q0007000100027200015Q00101C3Q000800010006752Q010001000100012Q0084017Q003800025Q0020080102000200090026390102004D00010003000437012Q004D00012Q0084010200013Q00124A0003000A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q00020002000100127F0102000D3Q00202Q00020002000E00122Q0003000F6Q0002000200014Q000200013Q00122Q000300106Q00020002000100122Q000200113Q000272000300023Q000272000400034Q00F500020004000200122Q000300123Q00122Q000400136Q00058Q0003000500014Q000300013Q00122Q000400146Q00030002000100122Q000300153Q00122Q000400166Q00030002000100122Q0003000B3Q00122Q0004000C6Q00030002000100122Q0003000D3Q00202Q00030003000E00122Q000400176Q00030002000100122Q000300186Q00030001000200062Q0003006200013Q000437012Q006200010020080104000300090026390104006200010013000437012Q006200010012EB000400194Q008401056Q0084010600024Q0040010400060001000437012Q006200012Q003800025Q0020080102000200090026390102006000010013000437012Q006000012Q0084010200013Q00124A0003001A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q0002000200010012BE0002000D3Q00202Q00020002000E00122Q0003001B6Q00020002000100122Q000200196Q00038Q000400016Q00020004000100044Q006200010012EB0002001C5Q000102000100012Q00D300025Q00129F000200013Q0012430002001D3Q00129F000200024Q00583Q00013Q00043Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q0012EB000100013Q00061E2Q01000900013Q000437012Q000900010012EB000100013Q0020082Q010001000200061E2Q01000900013Q000437012Q000900010012EB000100013Q00101C000100034Q00583Q00017Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q003800015Q0020082Q010001000100061E2Q01000900013Q000437012Q000900010012EB000100024Q003800025Q0020080102000200012Q008401036Q00402Q01000300012Q00583Q00017Q00023Q0003043Q007461736B03043Q007761697401073Q001214000100013Q00202Q0001000100024Q00028Q0001000200014Q000100016Q000100028Q00017Q00013Q00030E3Q0073652Q6C496E50726F6772652Q7300033Q0012EB3Q00014Q00FF3Q00024Q00583Q00017Q00363Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030B3Q00434F4E4649475F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C6503093Q004661726D54722Q657300030A3Q004661726D53746F6E6573030E3Q0054656C65706F727448656967687403063Q006E756D62657203133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A6503043Q006D61746803053Q00636C616D7003053Q00666C2Q6F72026Q003440026Q005E4003113Q00426C6F636B65645A6F6E6543656E746572026Q00084003073Q00566563746F72332Q033Q006E6577026Q00F03F027Q0040030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03063Q00737472696E6703153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F7003083Q005569595363616C65030A3Q0073617665645569506F7303053Q005544696D3203083Q005569585363616C65028Q0003093Q005569584F2Q66736574026Q00304003093Q005569594F2Q6673657400D63Q0012EB3Q00014Q0023012Q0001000200061E012Q000900013Q000437012Q000900010012EB3Q00023Q0012EB000100034Q00063Q000200020006F23Q000A00010001000437012Q000A00012Q00583Q00013Q0012EB3Q00043Q00027200016Q00FC3Q0002000100061E012Q001400013Q000437012Q001400010012EB000200054Q0084010300014Q00060002000200020026BF0002001500010006000437012Q001500012Q00583Q00013Q0020080102000100070026390102001B00010008000437012Q001B00010020080102000100090026BF0002001B00010008000437012Q001B00010012EB000200053Q00200801030001000A2Q0006000200020002002639010200220001000B000437012Q0022000100200801020001000A00129F0002000A3Q0012EB000200053Q00200801030001000C2Q0006000200020002002639010200290001000B000437012Q0029000100200801020001000C00129F0002000C3Q00200801020001000D0026BF0002002E00010008000437012Q002E000100200801020001000D00129F0002000D3Q00200801020001000E0026BF0002003300010008000437012Q0033000100200801020001000E00129F0002000E3Q00200801020001000F0026BF0002003800010008000437012Q0038000100200801020001000F00129F0002000F3Q0020080102000100100026BF0002003D00010008000437012Q003D000100200801020001001000129F000200103Q0012EB000200053Q0020080103000100112Q0006000200020002002639010200440001000B000437012Q0044000100200801020001001100129F000200113Q0012EB000200053Q0020080103000100122Q00060002000200020026390102004B0001000B000437012Q004B000100200801020001001200129F000200123Q0020080102000100130026BF0002005000010008000437012Q0050000100200801020001001300129F000200133Q0020080102000100140026BF0002005500010008000437012Q0055000100200801020001001400129F000200143Q0020080102000100150026BF0002005A00010008000437012Q005A000100200801020001001500129F000200153Q0020080102000100160026BF0002005F00010008000437012Q005F000100200801020001001600129F000200163Q0020080102000100170026BF0002006400010008000437012Q0064000100200801020001001700129F000200173Q0020080102000100180026BF0002006900010008000437012Q0069000100200801020001001800129F000200183Q0012EB000200053Q0020080103000100192Q0006000200020002002639010200780001000B000437012Q007800010012EB0002001A3Q00207401020002001B00122Q0003001A3Q00202Q00030003001C00202Q0004000100194Q00030002000200122Q0004001D3Q00122Q0005001E6Q00020005000200122Q000200193Q0012EB000200053Q00200801030001001F2Q00060002000200020026390102008B00010006000437012Q008B000100200801020001001F2Q00A7000200023Q000E2A0120008B00010002000437012Q008B00010012EB000200213Q00207600020002002200202Q00030001001F00202Q00030003002300202Q00040001001F00202Q00040004002400202Q00050001001F00202Q0005000500204Q00020005000200122Q0002001F3Q0020080102000100250026BF0002009000010008000437012Q0090000100200801020001002500129F000200253Q0012EB000200053Q0020080103000100262Q0006000200020002002639010200970001000B000437012Q0097000100200801020001002600129F000200263Q0012EB000200053Q0020080103000100272Q00060002000200020026390102009E00010028000437012Q009E000100200801020001002700129F000200273Q0020080102000100290026BF000200A300010008000437012Q00A3000100200801020001002900129F000200293Q0012EB000200053Q00200801030001002A2Q0006000200020002002639010200B50001000B000437012Q00B500010012EB0002001A3Q0020B600020002001B00122Q0003001A3Q00202Q00030003001C00202Q00040001002A4Q00030002000200122Q000400233Q00122Q0005001E6Q00020005000200122Q0002002A3Q00122Q0002002A3Q00202Q00020002002C00122Q0002002B3Q00200801020001002D0026BF000200BA00010008000437012Q00BA000100200801020001002D00129F0002002D3Q00200801020001002E0026BF000200BF00010008000437012Q00BF000100200801020001002E00129F0002002E3Q0012EB000200053Q00200801030001002F2Q0006000200020002002639010200D50001000B000437012Q00D500010012EB000200313Q0020080102000200220020080103000100320006F2000300CA00010001000437012Q00CA0001001243000300333Q0020080104000100340006F2000400CE00010001000437012Q00CE0001001243000400353Q00200801050001002F0020080106000100360006F2000600D300010001000437012Q00D30001001243000600334Q003F01020006000200129F000200304Q00583Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030B3Q00434F4E4649475F46494C4500083Q0012463Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00043Q0003043Q007469636B030D3Q006C6173745761726E696E674174025Q00804640030C3Q006661726D5761726E696E677302113Q001232010200016Q00020001000200122Q000300026Q000300033Q00062Q0003000C00013Q000437012Q000C00010012EB000300024Q00AC000300034Q00490003000200030026230003000C00010003000437012Q000C00012Q00583Q00013Q0012EB000300024Q004501033Q00020012EB000300044Q004501033Q00012Q00583Q00017Q00023Q00030C3Q006661726D5761726E696E67730001033Q0012EB000100013Q00200500013Q00022Q00583Q00017Q00083Q0003053Q007061697273030C3Q006661726D5761726E696E677303053Q007461626C6503063Q00696E7365727403043Q00E280A22003043Q00736F727403063Q00636F6E63617403013Q000A00194Q0064016Q00122Q000100013Q00122Q000200026Q00010002000300044Q000C00010012EB000600033Q0020910006000600044Q00075Q00122Q000800056Q000900056Q0008000800094Q00060008000100067C2Q01000500010002000437012Q000500010012EB000100033Q00200D0001000100064Q00028Q00010002000100122Q000100033Q00202Q0001000100074Q00025Q00122Q000300086Q000100036Q00019Q0000017Q00033Q0003053Q0073746F6E6503133Q0053746F6E6554656C65706F7274486569676874030E3Q0054656C65706F727448656967687401073Q002639012Q000400010001000437012Q000400010012EB000100024Q00FF000100023Q0012EB000100034Q00FF000100024Q00583Q00017Q00063Q00030F3Q0063616368656454722Q65436F756E74028Q00030E3Q00D0B4D0B5D180D0B5D0B2D18CD18F03103Q0063616368656453746F6E65436F756E74030A3Q00D0BAD0B0D0BCD0BDD0B8030A3Q00D0BFD0BED0B8D181D0BA000D3Q0012EB3Q00013Q000E790102000500013Q000437012Q000500010012433Q00034Q00FF3Q00023Q0012EB3Q00043Q000E790102000A00013Q000437012Q000A00010012433Q00054Q00FF3Q00023Q0012433Q00064Q00FF3Q00024Q00583Q00017Q00033Q0003123Q0055736572446973636F7264576562682Q6F6B034Q00030B3Q004B45595F574542482Q4F4B000B3Q0012EB3Q00013Q00061E012Q000800013Q000437012Q000800010012EB3Q00013Q0026BF3Q000800010002000437012Q000800010012EB3Q00014Q00FF3Q00023Q0012EB3Q00034Q00FF3Q00024Q00583Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503123Q007363686564756C6553617665436F6E66696700083Q0012EB3Q00014Q0023012Q000100020006F23Q000500010001000437012Q000500012Q00583Q00013Q0012EB3Q00025Q00012Q000100012Q00583Q00017Q00093Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030E3Q00576F726C6454656C65706F727473030B3Q0054656C65706F7274506164030D3Q0054656C65706F72744D6F64656C2Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734100293Q0012403Q00013Q00206Q000200122Q000200038Q0002000200064Q000800010001000437012Q000800012Q00AE000100014Q00FF000100023Q0020BC00013Q0002001243000300044Q003F2Q01000300020006F20001000F00010001000437012Q000F00012Q00AE000200024Q00FF000200023Q0020BC000200010002001243000400054Q003F0102000400020006F20002001600010001000437012Q001600012Q00AE000300034Q00FF000300023Q0020BC000300020002001243000500064Q003F0103000500020006F20003001D00010001000437012Q001D00012Q00AE000400044Q00FF000400023Q0020BC000400030007001243000600084Q003F01040006000200061E0104002300013Q000437012Q002300012Q00FF000300023Q0020BC000400030009001264000600086Q000700016Q000400076Q00049Q0000017Q00033Q0003133Q005669727475616C496E7075744D616E6167657203043Q0067616D65030A3Q004765745365727669636500063Q00122C012Q00023Q00206Q000300122Q000200018Q0002000200124Q00018Q00017Q00023Q0003133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00073Q0012EB3Q00013Q00061E012Q000600013Q000437012Q000600010012EB3Q00023Q00027200016Q00313Q000200012Q00583Q00013Q00013Q00063Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D65000A3Q0012FA3Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00033Q0003093Q006D6F75736548656C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00103Q0012EB3Q00013Q0006F23Q000400010001000437012Q000400012Q00583Q00013Q0012EB3Q00023Q00061E012Q000A00013Q000437012Q000A00010012EB3Q00033Q00027200016Q00313Q000200010012EB3Q00033Q000272000100014Q00313Q000200012Q00D37Q00129F3Q00014Q00583Q00013Q00023Q00063Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F75736559028Q0003043Q0067616D65000A3Q001278012Q00013Q00206Q000200122Q000200033Q00122Q000300043Q00122Q000400056Q00055Q00122Q000600063Q00122Q000700058Q000700016Q00017Q00033Q0003063Q00747970656F66030D3Q006D6F7573653172656C6561736503083Q0066756E6374696F6E00083Q0012EB3Q00013Q0012EB000100024Q00063Q00020002002639012Q000700010003000437012Q000700010012EB3Q00025Q00012Q000100012Q00583Q00017Q00083Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900133Q0012EB3Q00013Q002008014Q000200061E012Q000900013Q000437012Q000900010012EB3Q00013Q002008014Q00020020BC5Q0003001243000200044Q003F012Q000200020006F23Q000C00010001000437012Q000C00012Q00583Q00013Q0012EB000100063Q00200200010001000700104Q0005000100122Q000100063Q00202Q00010001000700104Q000800016Q00017Q00023Q00030F3Q00426C6F636B65645A6F6E6553697A65027Q004000043Q0012EB3Q00013Q0020DA5Q00022Q00FF3Q00024Q00583Q00017Q00043Q0003113Q00426C6F636B65645A6F6E6543656E74657203163Q00676574426C6F636B65645A6F6E6548616C6653697A6503073Q00566563746F72332Q033Q006E657700193Q0012EB3Q00013Q0006F23Q000500010001000437012Q000500012Q00AE3Q00014Q00713Q00033Q0012EB3Q00024Q0046012Q0001000200122Q000100013Q00122Q000200033Q00202Q0002000200044Q00038Q00048Q00058Q0002000500024Q00010001000200122Q000200013Q00122Q000300033Q00202Q0003000300044Q00048Q00058Q00068Q0003000600024Q0002000200034Q000100038Q00017Q00063Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403113Q00426C6F636B65645A6F6E6543656E74657203143Q00676574426C6F636B65645A6F6E654D696E4D617803013Q005803013Q005903013Q005A012E3Q0012EB000100013Q00061E2Q01000800013Q000437012Q0008000100061E012Q000800013Q000437012Q000800010012EB000100023Q0006F20001000A00010001000437012Q000A00012Q00D300016Q00FF000100023Q0012EB000100034Q003E00010001000200061E2Q01001000013Q000437012Q001000010006F20002001200010001000437012Q001200012Q00D300036Q00FF000300023Q00200801033Q00040020080104000100040006CA0004002A00010003000437012Q002A000100200801033Q00040020080104000200040006CA0003002A00010004000437012Q002A000100200801033Q00050020080104000100050006CA0004002A00010003000437012Q002A000100200801033Q00050020080104000200050006CA0003002A00010004000437012Q002A000100200801033Q00060020080104000100060006CA0004002A00010003000437012Q002A000100200801033Q00060020080104000200060006C20003000200010004000437012Q002B00012Q001B00036Q00D3000300014Q00FF000300024Q00583Q00017Q00023Q00030D3Q006765744E6F646543656E74657203123Q006973506F73496E426C6F636B65645A6F6E65010A3Q0012EB000100014Q008401026Q000600010002000200065E0002000800010001000437012Q000800010012EB000200024Q0084010300014Q00060002000200022Q00FF000200024Q00583Q00017Q00083Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203083Q00496E7374616E63652Q033Q006E657703063Q00466F6C64657203043Q004E616D6503063Q00506172656E7400113Q001243012Q00013Q00206Q000200122Q000200038Q0002000200064Q000F00010001000437012Q000F00010012EB000100043Q0020522Q010001000500122Q000200066Q0001000200026Q00013Q00122Q000100033Q00104Q0007000100122Q000100013Q00104Q000800012Q00FF3Q00024Q00583Q00017Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403053Q007063612Q6C000C3Q0012EB3Q00013Q00061E012Q000800013Q000437012Q000800010012EB3Q00023Q00027200016Q00313Q000200012Q00AE7Q00129F3Q00013Q0012EB3Q00023Q000272000100014Q00313Q000200012Q00583Q00013Q00023Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403073Q0044657374726F7900043Q0012EB3Q00013Q0020BC5Q00022Q00313Q000200012Q00583Q00017Q00043Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203073Q0044657374726F7900093Q001225012Q00013Q00206Q000200122Q000200038Q0002000200064Q000800013Q000437012Q000800010020BC00013Q00042Q00310001000200012Q00583Q00017Q00203Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403113Q00426C6F636B65645A6F6E6543656E74657203183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203153Q00626C6F636B65645A6F6E6556697375616C5061727403063Q00506172656E7403083Q00496E7374616E63652Q033Q006E657703043Q005061727403043Q004E616D65030A3Q00416E746954505A6F6E6503083Q00416E63686F7265642Q01030A3Q0043616E436F2Q6C696465010003083Q0043616E517565727903083Q0043616E546F756368030A3Q0043617374536861646F7703083Q004D6174657269616C03043Q00456E756D030A3Q00466F7263654669656C6403053Q00436F6C6F7203063Q00436F6C6F723303073Q0066726F6D524742025Q00E06F40025Q00805140030C3Q005472616E73706172656E6379020AD7A3703D0AE73F03043Q0053697A6503073Q00566563746F7233030F3Q00426C6F636B65645A6F6E6553697A6503063Q00434672616D6500453Q0012EB3Q00013Q00061E012Q000600013Q000437012Q000600010012EB3Q00023Q0006F23Q000900010001000437012Q000900010012EB3Q00035Q00012Q000100012Q00583Q00013Q0012EB3Q00044Q0023012Q000100020012EB000100053Q00061E2Q01001200013Q000437012Q001200010012EB000100053Q0020082Q01000100060006F20001003400010001000437012Q003400010012EB000100073Q00205900010001000800122Q000200096Q00010002000200122Q000100053Q00122Q000100053Q00302Q0001000A000B00122Q000100053Q00302Q0001000C000D00122Q000100053Q00302Q0001000E000F0012EB000100053Q00306000010010000F00122Q000100053Q00302Q00010011000F00122Q000100053Q00302Q00010012000F00122Q000100053Q00122Q000200143Q00202Q00020002001300202Q00020002001500102Q0001001300020012EB000100053Q00122Q010200173Q00202Q00020002001800122Q000300193Q00122Q0004001A3Q00122Q0005001A6Q00020005000200102Q00010016000200122Q000100053Q00302Q0001001B001C00122Q000100053Q00101C000100063Q0012EB000100053Q0012CE0002001E3Q00202Q00020002000800122Q0003001F3Q00122Q0004001F3Q00122Q0005001F6Q00020005000200102Q0001001D000200122Q000100053Q00122Q000200203Q00202Q0002000200080012EB000300024Q005F01020002000200102Q00010020000200122Q000100053Q00302Q0001001B001C6Q00017Q00083Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403113Q00426C6F636B65645A6F6E6543656E74657203083Q00506F736974696F6E03173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E66696700163Q0012EB3Q00013Q002008014Q000200061E012Q000900013Q000437012Q000900010012EB3Q00013Q002008014Q00020020BC5Q0003001243000200044Q003F012Q000200020006F23Q000D00010001000437012Q000D00012Q00D300016Q00FF000100023Q0020082Q013Q0006001245000100053Q00122Q000100076Q00010001000100122Q000100086Q0001000100014Q000100016Q000100028Q00017Q000B3Q0003123Q006973506F73496E426C6F636B65645A6F6E6503063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403063Q00434672616D652Q033Q006E657703163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747901203Q0012EB000100014Q008401026Q000600010002000200061E2Q01000600013Q000437012Q000600012Q00583Q00013Q0012EB000100023Q0020082Q010001000300061E2Q01000F00013Q000437012Q000F00010012EB000100023Q0020082Q01000100030020BC000100010004001243000300054Q003F2Q010003000200061E2Q01001300013Q000437012Q001300010006F23Q001400010001000437012Q001400012Q00583Q00013Q0012EB000200063Q0020F00002000200074Q00038Q00020002000200102Q00010006000200122Q000200093Q00202Q00020002000A00102Q00010008000200122Q000200093Q00202Q00020002000A00102Q0001000B00026Q00017Q000A3Q0003043Q007469636B03123Q0073686F756C644661726D436F6E74696E756503043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F0002293Q0012EB000200014Q00230102000100022Q0016010200023Q0012EB000300014Q00230103000100020006340003001F00010002000437012Q001F000100061E2Q01001000013Q000437012Q001000010012EB000300024Q0084010400014Q00060003000200020006F20003001000010001000437012Q001000012Q00D300036Q00FF000300023Q0012EB000300033Q0020E600030003000400122Q000400053Q00202Q00040004000600122Q000500073Q00122Q000600053Q00202Q00060006000800122Q000700093Q00122Q000800016Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q000300010026BF000100260001000A000437012Q002600010012EB000300024Q0084010400014Q0006000300020002000437012Q002700012Q001B00036Q00D3000300014Q00FF000300024Q00583Q00017Q000A3Q00030F3Q006D616E75616C53652Q6C546F6B656E03043Q007469636B030E3Q0073652Q6C496E50726F6772652Q7303043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F01283Q0012EB000100013Q0012EB000200024Q00230102000100022Q0016010200023Q0012EB000300024Q00230103000100020006340003001F00010002000437012Q001F00010012EB000300013Q00067D0001000E00010003000437012Q000E00010012EB000300033Q0006F20003001000010001000437012Q001000012Q00D300036Q00FF000300023Q0012EB000300043Q0020E600030003000500122Q000400063Q00202Q00040004000700122Q000500083Q00122Q000600063Q00202Q00060006000900122Q0007000A3Q00122Q000800026Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q000400010012EB000300013Q00067D0001002400010003000437012Q002400010012EB000300033Q000437012Q002600012Q001B00036Q00D3000300014Q00FF000300024Q00583Q00017Q000B3Q0003143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274001F3Q0012EB3Q00014Q0023012Q0001000200061E012Q000F00013Q000437012Q000F00010020082Q013Q00030012DF000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100023Q00122Q000100026Q000100023Q0012EB000100083Q0020082Q010001000900061E2Q01001800013Q000437012Q001800010012EB000100083Q0020082Q01000100090020BC00010001000A0012430003000B4Q003F2Q010003000200061E2Q01001E00013Q000437012Q001E000100200801020001000300129F000200023Q0012EB000200024Q00FF000200024Q00583Q00017Q00123Q00030B3Q00687562506F736974696F6E03143Q0067657454656C65706F7274537061776E5061727403083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q0069706169727303053Q00537061776E030D3Q00537061776E4C6F636174696F6E2Q033Q0048756203093Q00776F726B7370616365030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734103123Q0063617074757265487562506F736974696F6E026Q00144000483Q0012EB3Q00013Q00061E012Q000500013Q000437012Q000500010012EB3Q00014Q00FF3Q00023Q0012EB3Q00024Q0023012Q0001000200061E012Q001400013Q000437012Q001400010020082Q013Q00030012DF000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100013Q00122Q000100016Q000100023Q0012EB000100084Q0025000200033Q00122Q000300093Q00122Q0004000A3Q00122Q0005000B6Q0002000300012Q00FC000100020003000437012Q003A00010012EB0006000C3Q0020BC00060006000D2Q0084010800054Q003F01060008000200061E0106003A00013Q000437012Q003A00010020BC00070006000E0012430009000F4Q003F01070009000200061E0107002900013Q000437012Q002900010006140107002D00010006000437012Q002D00010020BC0007000600100012430009000F4Q00D3000A00014Q003F0107000A000200061E0107003A00013Q000437012Q003A00010020080108000700030012DF000900043Q00202Q00090009000500122Q000A00063Q00122Q000B00073Q00122Q000C00066Q0009000C00024Q00080008000900122Q000800013Q00122Q000800016Q000800023Q00067C2Q01001C00010002000437012Q001C00010012EB000100114Q00232Q01000100020006F20001004600010001000437012Q004600010012EB000100043Q00207E00010001000500122Q000200063Q00122Q000300123Q00122Q000400066Q0001000400022Q00FF000100024Q00583Q00017Q000D3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030E3Q00676574487562506F736974696F6E03073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030F3Q004855425F4E4541525F52414449555300283Q0012EB3Q00013Q002008014Q000200061E012Q000900013Q000437012Q000900010012EB3Q00013Q002008014Q00020020BC5Q0003001243000200044Q003F012Q000200020012EB000100054Q00232Q010001000200061E012Q000F00013Q000437012Q000F00010006F20001001100010001000437012Q001100012Q00D300026Q00FF000200023Q0012EB000200063Q00206C01020002000700202Q00033Q000800202Q00030003000900202Q00040001000A00202Q00053Q000800202Q00050005000B4Q00020005000200122Q000300063Q00202Q00030003000700202Q00040001000900202Q00050001000A00202Q00060001000B4Q0003000600024Q00040002000300202Q00040004000C00122Q0005000D3Q00062Q0004000200010005000437012Q002500012Q001B00046Q00D3000400014Q00FF000400024Q00583Q00017Q000A3Q0003093Q0069734E65617248756203143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q000840030D3Q0074656C65706F7274487270546F030E3Q00676574487562506F736974696F6E001B3Q0012EB3Q00014Q0023012Q0001000200061E012Q000500013Q000437012Q000500012Q00583Q00013Q0012EB3Q00024Q0023012Q0001000200061E012Q001600013Q000437012Q001600010020082Q013Q0004001280000200053Q00202Q00020002000600122Q000300073Q00122Q000400083Q00122Q000500076Q0002000500024Q00010001000200122Q000100033Q00122Q000100093Q00122Q000200036Q0001000200016Q00013Q0012EB000100093Q0012EB0002000A4Q0053000200014Q008500013Q00012Q00583Q00017Q000E4Q0003093Q006661726D50686173652Q033Q0068756203103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q0063752Q72656E7454617267657450617274030D3Q0074656C65706F7274546F487562030E3Q0048756257616974456E61626C6564030C3Q004855425F574149545F4D494E03043Q006D61746803063Q0072616E646F6D030C3Q004855425F574149545F4D415803113Q00696E74652Q7275707469626C655761697402253Q0026392Q01000300010001000437012Q000300012Q00D3000100013Q001243000200033Q00122E010200023Q00122Q000200046Q00020001000100122Q000200056Q00020001000100122Q000200066Q0002000100014Q000200023Q00122Q000200073Q00062Q0001001100013Q000437012Q001100010012EB000200085Q000102000100010012EB000200093Q0006F20002001600010001000437012Q001600012Q00D3000200014Q00FF000200023Q0012EB0002000A3Q00122Q0003000B3Q00202Q00030003000C4Q00030001000200122Q0004000D3Q00122Q0005000A6Q0004000400054Q0003000300044Q00020002000300122Q0003000E6Q000400026Q00058Q000300056Q00039Q0000017Q00033Q00030B3Q00687562526573745761697403093Q006661726D506861736503043Q0069646C65010C3Q0012EB000100014Q008401026Q00060001000200020006F20001000700010001000437012Q000700012Q00D300016Q00FF000100023Q001243000100033Q00129F000100024Q00D3000100014Q00FF000100024Q00583Q00017Q00023Q0003073Q00557365464B6579030B3Q006175746F4641637469766500063Q0012EB3Q00013Q0006F23Q000400010001000437012Q000400010012EB3Q00024Q00FF3Q00024Q00583Q00017Q00033Q00030C3Q0073686F756C645072652Q734603133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C000F3Q0012EB3Q00014Q0023012Q000100020006F23Q000500010001000437012Q000500012Q00583Q00013Q0012EB3Q00023Q00061E012Q000B00013Q000437012Q000B00010012EB3Q00033Q00027200016Q00313Q000200010012EB3Q00033Q000272000100014Q00313Q000200012Q00583Q00013Q00023Q00093Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D6503043Q007461736B03043Q007761697402B81E85EB51B89E3F00173Q0012EC3Q00013Q00206Q00024Q000200013Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q0005000100124Q00073Q002008014Q0008001243000100094Q00313Q000200010012FA3Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00023Q0003063Q006B657974617003043Q00564B5F4600043Q0012EB3Q00013Q0012EB000100024Q00313Q000200012Q00583Q00017Q000A3Q00028Q0003093Q006D6F75736548656C6403043Q006D6174682Q033Q00616273030A3Q00686F6C644D6F75736558027Q0040030A3Q00686F6C644D6F7573655903103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C022D3Q0006140102000300013Q000437012Q00030001001243000200013Q0006F20001000600010001000437012Q00060001001243000100014Q0084012Q00023Q0012EB000200023Q00061E0102001900013Q000437012Q001900010012EB000200033Q00203A00020002000400122Q000300056Q000300036Q00020002000200262Q0002001900010006000437012Q001900010012EB000200033Q00203A00020002000400122Q000300076Q0003000300014Q00020002000200262Q0002001900010006000437012Q001900012Q00583Q00013Q0012EB000200085Q000102000100010012EB000200093Q00061E0102002400013Q000437012Q002400010012EB0002000A3Q00067501033Q000100022Q0084017Q0084012Q00014Q0031000200020001000437012Q002700010012EB0002000A3Q000272000300014Q00310002000200012Q00D3000200013Q001270010200026Q00025Q00122Q000100073Q00122Q000200058Q00013Q00023Q00043Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D65000A3Q0012FD3Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q000700016Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F757365317072652Q7303083Q0066756E6374696F6E00083Q0012EB3Q00013Q0012EB000100024Q00063Q00020002002639012Q000700010003000437012Q000700010012EB3Q00025Q00012Q000100012Q00583Q00017Q00033Q0003103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C02133Q0012EB000200015Q000102000100010012EB000200023Q00061E0102000F00013Q000437012Q000F000100061E012Q000F00013Q000437012Q000F000100061E2Q01000F00013Q000437012Q000F00010012EB000200033Q00067501033Q000100022Q0084017Q0084012Q00014Q0031000200020001000437012Q001200010012EB000200033Q000272000300014Q00310002000200012Q00583Q00013Q00023Q00073Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D6503043Q007461736B03043Q0077616974029A5Q99A93F00173Q001221012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q0007000100124Q00053Q00206Q000600122Q000100078Q0002000100124Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q00055Q00122Q000600043Q00122Q000700038Q000700016Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F75736531636C69636B03083Q0066756E6374696F6E00083Q0012EB3Q00013Q0012EB000100024Q00063Q00020002002639012Q000700010003000437012Q000700010012EB3Q00025Q00012Q000100012Q00583Q00017Q00073Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D65726103143Q00576F726C64546F56696577706F7274506F696E74030A3Q0047756953657276696365030B3Q00476574477569496E73657403013Q005803013Q005901163Q0006F23Q000400010001000437012Q000400012Q00AE000100014Q00FF000100023Q0012EB000100013Q0020082Q01000100020006F20001000A00010001000437012Q000A00012Q00AE000200024Q00FF000200023Q0020BC0002000100032Q00D700048Q00020004000200122Q000300043Q00202Q0003000300054Q00030002000200202Q00040002000600202Q00050002000700202Q0006000300074Q0005000500064Q000400038Q00017Q00083Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D657261030A3Q0047756953657276696365030B3Q00476574477569496E736574030C3Q0056696577706F727453697A6503013Q0058026Q00E03F03013Q005900123Q0012EB3Q00013Q002008014Q00020006F23Q000600010001000437012Q000600012Q00AE000100014Q00FF000100023Q0012EB000100033Q0020B70001000100044Q00010002000200202Q00023Q000500202Q00030002000600202Q00030003000700202Q00040002000800202Q00040004000700202Q0005000100084Q0004000400054Q000300034Q00583Q00017Q00043Q002Q033Q0049734103083Q00426173655061727403083Q00506F736974696F6E03163Q0046696E6446697273744368696C64576869636849734101143Q0006F23Q000400010001000437012Q000400012Q00AE000100014Q00FF000100023Q0020BC00013Q0001001243000300024Q003F2Q010003000200061E2Q01000B00013Q000437012Q000B00010020082Q013Q00032Q00FF000100023Q0020BC00013Q0004001243000300024Q00D3000400014Q003F2Q010004000200061E2Q01001300013Q000437012Q001300010020080102000100032Q00FF000200024Q00583Q00017Q00063Q00030F3Q0067657450617274506F736974696F6E030B3Q0041696D417454617267657403113Q0063752Q72656E745461726765745061727403063Q00506172656E74030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73011F3Q0012072Q0100016Q00028Q00010002000200122Q000200023Q00062Q0002001200013Q000437012Q001200010012EB000200033Q00061E0102001200013Q000437012Q001200010012EB000200033Q00200801020002000400061E0102001200013Q000437012Q001200010012EB000200013Q0012EB000300034Q00060002000200020006142Q01001200010002000437012Q001200010012EB000200054Q0084010300014Q00FC0002000200030006F20002001B00010001000437012Q001B00010012EB000400064Q003E0004000100052Q0084010300054Q0084010200044Q0084010400024Q0084010500034Q0071000400034Q00583Q00017Q00073Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403043Q004465616403053Q0056616C75652Q0103063Q004865616C7468028Q00011E3Q0020BC00013Q0001001243000300024Q003F2Q01000300020006F20001000700010001000437012Q000700012Q00D300026Q00FF000200023Q0020BC000200010001001243000400034Q003F01020004000200061E0102001100013Q000437012Q001100010020080103000200040026390103001100010005000437012Q001100012Q00D300036Q00FF000300023Q0020BC000300010001001243000500064Q003F01030005000200061E0103001B00013Q000437012Q001B00010020080104000300040026550004001B00010007000437012Q001B00012Q00D300046Q00FF000400024Q00D3000400014Q00FF000400024Q00583Q00017Q00043Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403063Q004865616C746803053Q0056616C7565010F3Q00065E0001000500013Q000437012Q000500010020BC00013Q0001001243000300024Q003F2Q010003000200065E0002000A00010001000437012Q000A00010020BC000200010001001243000400034Q003F01020004000200061E0102000E00013Q000437012Q000E00010020080103000200042Q00FF000300024Q00583Q00017Q00043Q00030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365029Q00074Q007D016Q00124Q00019Q003Q00124Q00023Q00124Q00043Q00124Q00038Q00017Q00083Q0003073Q00557365464B6579030B3Q006175746F46416374697665030D3Q006765744E6F64654865616C746803043Q007469636B030F3Q00737475636B4C6173744865616C746800030A3Q00737475636B53696E6365030F3Q00535455434B5F465F5345434F4E445301213Q0012EB000100013Q00061E2Q01000600013Q000437012Q000600012Q00D300015Q00129F000100024Q00583Q00013Q0012EB000100034Q008401026Q00060001000200020006F20001000C00010001000437012Q000C00012Q00583Q00013Q0012EB000200044Q00230102000100020012EB000300053Q0026BF0003001400010006000437012Q001400010012EB000300053Q0006340001001900010003000437012Q0019000100129F000100053Q00129F000200074Q00D300035Q00129F000300023Q000437012Q002000010012EB000300074Q00490003000200030012EB000400083Q0006CA0004002000010003000437012Q002000012Q00D3000300013Q00129F000300024Q00583Q00017Q00083Q0003063Q00697061697273030B3Q004765744368696C6472656E03043Q004E616D6503063Q00486974626F782Q033Q0049734103083Q00426173655061727403053Q007461626C6503063Q00696E7365727401174Q00202Q015Q00122Q000200013Q00202Q00033Q00024Q000300046Q00023Q000400044Q001300010020080107000600030026390107001300010004000437012Q001300010020BC000700060005001243000900064Q003F01070009000200061E0107001300013Q000437012Q001300010012EB000700073Q0020080107000700082Q0084010800014Q0084010900064Q004001070009000100067C0102000600010002000437012Q000600012Q00FF000100024Q00583Q00017Q00033Q002Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C645768696368497341010C3Q0020BC00013Q0001001243000300024Q003F2Q010003000200061E2Q01000600013Q000437012Q000600012Q00FF3Q00023Q0020BC00013Q0003001264000300026Q000400016Q000100046Q00019Q0000017Q00063Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403083Q00506F736974696F6E030B3Q00676574486974626F786573028Q00026Q00F03F01113Q0020BC00013Q0001001243000300024Q003F2Q010003000200061E2Q01000700013Q000437012Q000700010020080102000100032Q00FF000200023Q0012EB000200044Q008401036Q00060002000200022Q00A7000300023Q000E790105001000010003000437012Q001000010020080103000200060020080103000300032Q00FF000300024Q00583Q00017Q00073Q0003053Q007063612Q6C028Q00030F3Q00707573684661726D5761726E696E67030A3Q006E6F5F7461726765747303253Q00D09DD0B5D18220D186D0B5D0BBD0B5D0B920D0B4D0BBD18F20D0B4D0BED0B1D18BD187D0B803103Q00636C6561724661726D5761726E696E6703073Q006E6F5F6D6F6465001D4Q00AF8Q00AF00015Q0012EB000200013Q00067501033Q000100022Q0084017Q0084012Q00014Q00310002000200012Q00A700025Q000E790102000C00010002000437012Q000C00010006140102000D00013Q000437012Q000D00012Q0084010200014Q00A7000300023Q0026390103001500010002000437012Q001500010012EB000300033Q001243000400043Q001243000500054Q0040010300050001000437012Q001B00010012EB000300063Q00124A000400046Q00030002000100122Q000300063Q00122Q000400076Q0003000200012Q00FF000200024Q00583Q00013Q00013Q00163Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030F3Q00707573684661726D5761726E696E67030F3Q006E6F5F696E746572616374696F6E7303203Q00D09DD0B5D18220496E746572616374696F6E7320D0B220776F726B737061636503103Q00636C6561724661726D5761726E696E6703053Q004E6F64657303083Q006E6F5F6E6F64657303173Q00D09DD0B5D18220D0BFD0B0D0BFD0BAD0B8204E6F64657303043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C69766503133Q0069734E6F6465496E426C6F636B65645A6F6E6503053Q007461626C6503063Q00696E7365727403043Q006E6F646503043Q006B696E6403043Q0074722Q6503093Q005265736F757263657303053Q0073746F6E6500563Q0012403Q00013Q00206Q000200122Q000200038Q0002000200064Q000B00010001000437012Q000B00010012EB000100043Q001243000200053Q001243000300064Q00402Q01000300012Q00583Q00013Q0012EB000100073Q001235010200056Q00010002000100202Q00013Q000200122Q000300086Q00010003000200062Q0001001800010001000437012Q001800010012EB000200043Q001243000300093Q0012430004000A4Q00400102000400012Q00583Q00013Q0012EB000200073Q00124E010300096Q00020002000100202Q00020001000200122Q0004000B6Q00020004000200062Q0002003800013Q000437012Q003800010012EB0003000C3Q0020BC00040002000D2Q002E000400054Q00EE00033Q0005000437012Q003600010012EB0008000E4Q0084010900074Q000600080002000200061E0108003600013Q000437012Q003600010012EB0008000F4Q0084010900074Q00060008000200020006F20008003600010001000437012Q003600010012EB000800103Q0020F70008000800114Q00098Q000A3Q000200102Q000A0012000700302Q000A001300144Q0008000A000100067C0103002500010002000437012Q002500010020BC000300010002001243000500154Q003F01030005000200061E0103005500013Q000437012Q005500010012EB0004000C3Q0020BC00050003000D2Q002E000500064Q00EE00043Q0006000437012Q005300010012EB0009000E4Q0084010A00084Q000600090002000200061E0109005300013Q000437012Q005300010012EB0009000F4Q0084010A00084Q00060009000200020006F20009005300010001000437012Q005300010012EB000900103Q0020F70009000900114Q000A00016Q000B3Q000200102Q000B0012000800302Q000B001300164Q0009000B000100067C0104004200010002000437012Q004200012Q00583Q00017Q00043Q00028Q0003053Q007063612Q6C030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E74000D3Q0012433Q00013Q001243000100013Q0012EB000200023Q00067501033Q000100022Q0084017Q0084012Q00014Q002B01020002000100124Q00033Q00122Q000100046Q00028Q000300016Q000200038Q00013Q00013Q000A3Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E7303053Q004E6F64657303043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C697665026Q00F03F03093Q005265736F757263657300363Q0012403Q00013Q00206Q000200122Q000200038Q0002000200064Q000700010001000437012Q000700012Q00583Q00013Q0020BC00013Q0002001243000300044Q003F2Q01000300020006F20001000D00010001000437012Q000D00012Q00583Q00013Q0020BC000200010002001243000400054Q003F01020004000200061E0102002100013Q000437012Q002100010012EB000300063Q0020BC0004000200072Q002E000400054Q00EE00033Q0005000437012Q001F00010012EB000800084Q0084010900074Q000600080002000200061E0108001F00013Q000437012Q001F00012Q003800085Q0020360008000800092Q00C900085Q00067C0103001700010002000437012Q001700010020BC0003000100020012430005000A4Q003F01030005000200061E0103003500013Q000437012Q003500010012EB000400063Q0020BC0005000300072Q002E000500064Q00EE00043Q0006000437012Q003300010012EB000900084Q0084010A00084Q000600090002000200061E0109003300013Q000437012Q003300012Q0038000900013Q0020360009000900092Q00C9000900013Q00067C0104002B00010002000437012Q002B00012Q00583Q00017Q000C3Q00028Q00030E3Q00676574487562506F736974696F6E03063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403083Q00506F736974696F6E026Q00F03F03063Q00697061697273030D3Q006765744E6F646543656E74657203043Q006E6F646503093Q004D61676E697475646501324Q00A700015Q0026392Q01000500010001000437012Q000500012Q00AE000100014Q00FF000100023Q0012EB000100024Q00232Q01000100020012EB000200033Q00200801020002000400061E0102001000013Q000437012Q001000010012EB000200033Q0020080102000200040020BC000200020005001243000400064Q003F01020004000200061E0102001500013Q000437012Q001500010006F20001001500010001000437012Q001500010020082Q01000200070006F20001001900010001000437012Q0019000100200801033Q00082Q00FF000300024Q00AE000300043Q0012EB000500094Q008401066Q00FC000500020007000437012Q002B00010012EB000A000A3Q002008010B0009000B2Q0006000A0002000200061E010A002B00013Q000437012Q002B00012Q0049000B000A0001002008010B000B000C00061E0104002900013Q000437012Q00290001000634000B002B00010004000437012Q002B00012Q0084010300094Q00840104000B3Q00067C0105001E00010002000437012Q001E00010006140105003000010003000437012Q0030000100200801053Q00082Q00FF000500024Q00583Q00017Q00043Q00030C3Q00706174726F6C506F696E747303053Q007063612Q6C030B3Q00706174726F6C496E646578026Q00F03F00084Q00AF7Q00129F3Q00013Q0012EB3Q00023Q00027200016Q00313Q000200010012433Q00043Q00129F3Q00034Q00583Q00013Q00013Q00073Q0003063Q00697061697273030F3Q0067657456616C696454617267657473030D3Q006765744E6F646543656E74657203043Q006E6F646503053Q007461626C6503063Q00696E73657274030C3Q00706174726F6C506F696E747300123Q0012543Q00013Q00122Q000100026Q000100019Q00000200044Q000F00010012EB000500033Q0020080106000400042Q000600050002000200061E0105000F00013Q000437012Q000F00010012EB000600053Q0020080106000600060012EB000700074Q0084010800054Q004001060008000100067C012Q000500010002000437012Q000500012Q00583Q00017Q001A3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030C3Q00706174726F6C506F696E7473028Q00030B3Q00706174726F6C496E64657803073Q00566563746F72332Q033Q006E657703183Q0067657454656C65706F7274486569676874466F724B696E6403103Q006163746976655461726765744B696E64026Q00F03F030B3Q00736561726368416E676C65026Q66D63F030C3Q00736561726368526164697573026Q007940026Q005440026Q002E4003083Q00506F736974696F6E03043Q006D6174682Q033Q00636F732Q033Q0073696E03063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900573Q0012EB3Q00013Q002008014Q000200061E012Q000900013Q000437012Q000900010012EB3Q00013Q002008014Q00020020BC5Q0003001243000200044Q003F012Q000200020006F23Q000C00010001000437012Q000C00012Q00583Q00014Q00AE000100013Q0012EB000200054Q00A7000200023Q000E790106002900010002000437012Q002900010012EB000200053Q0012EB000300074Q00AC00020002000300061E0102001F00013Q000437012Q001F00010012EB000300083Q00203401030003000900122Q000400063Q00122Q0005000A3Q00122Q0006000B6Q00050002000200122Q000600066Q0003000600024Q0001000200030012EB000300073Q00201F00030003000C00122Q000300073Q00122Q000300073Q00122Q000400056Q000400043Q00062Q0004002900010003000437012Q002900010012430003000C3Q00129F000300073Q0006F20001004B00010001000437012Q004B00010012EB0002000D3Q00203600020002000E00129F0002000D3Q0012EB0002000F3Q000E790110003400010002000437012Q00340001001243000200113Q00129F0002000F3Q000437012Q003700010012EB0002000F3Q00203600020002001200129F0002000F3Q00200801023Q001300124B000300083Q00202Q00030003000900122Q000400143Q00202Q00040004001500122Q0005000D6Q00040002000200122Q0005000F6Q00040004000500122Q0005000A3Q00122Q0006000B6Q00050002000200122Q000600143Q00202Q00060006001600122Q0007000D6Q00060002000200122Q0007000F6Q0006000600074Q0003000600024Q0001000200030012EB000200173Q0020F00002000200094Q000300016Q00020002000200104Q0017000200122Q000200083Q00202Q00020002001900104Q0018000200122Q000200083Q00202Q00020002001900104Q001A00026Q00017Q00063Q002Q033Q0049734103053Q004D6F64656C03063Q0069706169727303103Q0044524F505F4D4F44454C5F48494E545303043Q004E616D6503043Q0066696E6401183Q0020BC00013Q0001001243000300024Q003F2Q01000300020006F20001000700010001000437012Q000700012Q00D300016Q00FF000100023Q0012EB000100033Q0012EB000200044Q00FC000100020003000437012Q0013000100200801063Q00050020BC0006000600062Q0084010800054Q003F01060008000200061E0106001300013Q000437012Q001300012Q00D3000600014Q00FF000600023Q00067C2Q01000B00010002000437012Q000B00012Q00D300016Q00FF000100024Q00583Q00017Q00093Q0003103Q006163746976655461726765744B696E6403043Q004E616D6503043Q0066696E64030F3Q00436F2Q7065725265736F7572636573030D3Q004C6561665265736F757263657303053Q0073746F6E6503093Q00462Q6F644D6F64656C030D3Q00572Q6F645265736F757263657303043Q0074722Q6501203Q0006F23Q000400010001000437012Q000400010012EB000100014Q00FF000100023Q0020082Q013Q00020020BC000200010003001243000400044Q003F0102000400020006F20002000F00010001000437012Q000F00010020BC000200010003001243000400054Q003F01020004000200061E0102001100013Q000437012Q00110001001243000200064Q00FF000200023Q0020BC000200010003001243000400074Q003F0102000400020006F20002001B00010001000437012Q001B00010020BC000200010003001243000400084Q003F01020004000200061E0102001D00013Q000437012Q001D0001001243000200094Q00FF000200023Q0012EB000200014Q00FF000200024Q00583Q00017Q00023Q00030C3Q0069676E6F72656444726F707303063Q00506172656E7401133Q0012EB000100014Q00AC000100013Q00061E2Q01000600013Q000437012Q000600012Q00D3000100014Q00FF000100023Q0020082Q013Q000200061E2Q01001000013Q000437012Q001000010012EB000100013Q00200801023Q00022Q00AC00010001000200061E2Q01001000013Q000437012Q001000012Q00D3000100014Q00FF000100024Q00D300016Q00FF000100024Q00583Q00017Q000B3Q00030C3Q0069676E6F72656444726F70732Q0103103Q006163746976655461726765744B696E6403063Q00506172656E742Q033Q0049734103053Q004D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C03053Q0073746F6E6503113Q0073652Q73696F6E53746F6E6544726F7073026Q00F03F03103Q0073652Q73696F6E54722Q6544726F7073011D3Q001211000100013Q00202Q00013Q000200122Q000100033Q00202Q00023Q000400062Q0002001300013Q000437012Q0013000100200801023Q00040020BC000200020005001243000400064Q003F01020004000200061E0102001300013Q000437012Q001300010012EB000200073Q00201101033Q00044Q0002000200024Q000100023Q00122Q000200013Q00202Q00033Q000400202Q0002000300020026392Q01001900010008000437012Q001900010012EB000200093Q00203600020002000A00129F000200093Q000437012Q001C00010012EB0002000B3Q00203600020002000A00129F0002000B4Q00583Q00017Q00063Q0003063Q00506172656E74030D3Q00697344726F7049676E6F72656403123Q006973506F73496E426C6F636B65645A6F6E6503083Q00506F736974696F6E03013Q0059026Q00244002223Q00061E012Q000500013Q000437012Q0005000100200801023Q00010006F20002000700010001000437012Q000700012Q00D300026Q00FF000200023Q0012EB000200024Q008401036Q000600020002000200061E0102000E00013Q000437012Q000E00012Q00D300026Q00FF000200023Q0012EB000200033Q00200801033Q00042Q000600020002000200061E0102001500013Q000437012Q001500012Q00D300026Q00FF000200023Q00061E2Q01001F00013Q000437012Q001F000100200801023Q00040020080102000200050020080103000100052Q0049000200020003000E790106001F00010002000437012Q001F00012Q00D300026Q00FF000200024Q00D3000200014Q00FF000200024Q00583Q00017Q00183Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403063Q0043616D657261030F3Q00707573684661726D5761726E696E6703093Q006E6F5F63616D657261032A3Q00D09DD0B5D1822043616D65726120E2809420D0BBD183D18220D0BDD0B520D0BDD0B0D0B9D0B4D0B5D0BD03103Q00636C6561724661726D5761726E696E6703063Q00697061697273030B3Q004765744368696C6472656E03133Q0069735265736F7572636544726F704D6F64656C03063Q00506172656E74030E3Q00676574436F2Q6C6563745061727403123Q00697356616C6964436F2Q6C65637444726F7003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030E3Q00434F2Q4C4543545F52414449555303053Q007461626C6503063Q00696E7365727403043Q00736F727401464Q00AF00015Q0006F23Q000400010001000437012Q000400012Q00FF000100023Q0012EB000200013Q0020BC000200020002001243000400034Q003F0102000400020006F20002000F00010001000437012Q000F00010012EB000300043Q001243000400053Q001243000500064Q00400103000500012Q00FF000100023Q0012EB000300073Q001249010400056Q00030002000100122Q000300083Q00202Q0004000200094Q000400056Q00033Q000500044Q003C00010012EB0008000A4Q0084010900074Q000600080002000200061E0108003C00013Q000437012Q003C000100200801080007000B00061E0108003C00013Q000437012Q003C00010012EB0008000C4Q0084010900074Q000600080002000200061E0108003C00013Q000437012Q003C00010012EB0009000D4Q0084010A00084Q0084010B6Q003F0109000B000200061E0109003C00013Q000437012Q003C00010012EB0009000E3Q00206B01090009000F00202Q000A0008001000202Q000A000A001100202Q000B3Q001200202Q000C0008001000202Q000C000C00134Q0009000C00024Q000900093Q00202Q00090009001400122Q000A00153Q00062Q0009003C0001000A000437012Q003C00010012EB000A00163Q002008010A000A00172Q0084010B00014Q0084010C00084Q0040010A000C000100067C0103001700010002000437012Q001700010012EB000300163Q0020080103000300182Q0084010400013Q00067501053Q000100012Q0084017Q00400103000500012Q00FF000100024Q00583Q00013Q00013Q00073Q0003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465021E3Q00126E010200013Q00202Q00020002000200202Q00033Q000300202Q0003000300044Q00045Q00202Q00040004000500202Q00053Q000300202Q0005000500064Q0002000500024Q00038Q00020002000300202Q00020002000700122Q000300013Q00202Q00030003000200202Q00040001000300202Q0004000400044Q00055Q00202Q00050005000500202Q00060001000300202Q0006000600064Q0003000600024Q00048Q00030003000400202Q00030003000700062Q0002001B00010003000437012Q001B00012Q001B00046Q00D3000400014Q00FF000400024Q00583Q00017Q00023Q00030D3Q006765744E6F646543656E74657203173Q0066696E6443616D6572615265736F7572636544726F7073010C3Q0012EB000100014Q008401026Q00060001000200020006F20001000700010001000437012Q000700012Q00AF00026Q00FF000200023Q0012EB000200024Q0084010300014Q0089000200034Q001001026Q00583Q00017Q00073Q0003113Q006D61726B44726F70436F2Q6C656374656403163Q0046696E6446697273744368696C645768696368497341030F3Q0050726F78696D69747950726F6D707403063Q00506172656E7403053Q007063612Q6C030C3Q0073686F756C645072652Q734603063Q007072652Q734601223Q0006F23Q000300010001000437012Q000300012Q00583Q00013Q0012EB000100014Q006100028Q00010002000100202Q00013Q000200122Q000300036Q000400016Q00010004000200062Q0001001500010001000437012Q0015000100200801023Q000400061E0102001500013Q000437012Q0015000100200801023Q000400201E00020002000200122Q000400036Q000500016Q0002000500024Q000100023Q00061E2Q01001B00013Q000437012Q001B00010012EB000200053Q00067501033Q000100012Q0084012Q00014Q00310002000200010012EB000200064Q002301020001000200061E0102002100013Q000437012Q002100010012EB000200075Q000102000100012Q00583Q00013Q00013Q00013Q0003133Q006669726570726F78696D69747970726F6D707400043Q0012EB3Q00014Q003800016Q00313Q000200012Q00583Q00017Q00163Q0003093Q006661726D506861736503073Q00636F2Q6C656374030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E7454617267657450617274030D3Q006765744E6F646543656E746572030C3Q0069676E6F72656444726F7073026Q00F03F026Q00344003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E65617203063Q0069706169727303123Q00697356616C6964436F2Q6C65637444726F7003083Q00506F736974696F6E030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C6557616974027B14AE47E17AB43F030B3Q00636F2Q6C65637450617274029A5Q99A93F029A5Q99B93F03133Q0073746F704368617261637465724D6F74696F6E02593Q0012DE000200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200076Q00038Q0002000200024Q00035Q00122Q000300083Q00122Q000300093Q00122Q0004000A3Q00122Q000500093Q00042Q0003005400010012EB0007000B4Q0084010800014Q00060007000200020006F20007001700010001000437012Q00170001000437012Q005400010012EB0007000C4Q008401086Q00060007000200022Q00A7000800073Q0026390108001E00010004000437012Q001E0001000437012Q005400010012EB0008000D4Q0084010900074Q00FC00080002000A000437012Q004A00010012EB000D000B4Q0084010E00014Q0006000D000200020006F2000D002800010001000437012Q00280001000437012Q004A00010012EB000D000E4Q0084010E000C4Q0084010F00024Q003F010D000F00020006F2000D002F00010001000437012Q002F0001000437012Q004A0001002008010D000C000F00122B000E00106Q000F000D6Q000E0002000100122Q000C00063Q00122Q000E00113Q00122Q000F00126Q001000016Q000E0010000200062Q000E003B00010001000437012Q003B0001000437012Q004A00010012EB000E00104Q0016000F000D6Q000E0002000100122Q000E00136Q000F000C6Q000E0002000100122Q000E00113Q00122Q000F00146Q001000016Q000E0010000200062Q000E004800010001000437012Q00480001000437012Q004A00012Q00AE000E000E3Q00129F000E00063Q00067C0108002200010002000437012Q002200010012EB000800113Q001243000900154Q0084010A00014Q003F0108000A00020006F20008005300010001000437012Q00530001000437012Q005400010004DD0003001100012Q00AE000300033Q00129F000300063Q0012EB000300165Q000103000100012Q00583Q00017Q00053Q0003063Q007072652Q7346030F3Q0067657441696D5363722Q656E506F7303083Q00557365436C69636B03073Q00636C69636B4174030B3Q00686F6C644D6F7573654174011A3Q0006F23Q000300010001000437012Q000300012Q00583Q00013Q0012EB000100014Q003D00010001000100122Q000100026Q00028Q00010002000200062Q0001000C00013Q000437012Q000C00010006F20002000D00010001000437012Q000D00012Q00583Q00013Q0012EB000300033Q00061E0103001500013Q000437012Q001500010012EB000300044Q0084010400014Q0084010500024Q0040010300050001000437012Q001900010012EB000300054Q0084010400014Q0084010500024Q00400103000500012Q00583Q00017Q00043Q0003063Q0069706169727303163Q00412Q73656D626C794C696E65617256656C6F6369747903093Q004D61676E6974756465026Q00F83F010F3Q0012EB000100014Q008401026Q00FC000100020003000437012Q000A0001002008010600050002002008010600060003000E790104000A00010006000437012Q000A00012Q00D300066Q00FF000600023Q00067C2Q01000400010002000437012Q000400012Q00D3000100014Q00FF000100024Q00583Q00017Q000F3Q0003093Q006661726D506861736503043Q0077616974030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403113Q00696E74652Q7275707469626C6557616974026Q00D03F03043Q007469636B026Q00084003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E656172030F3Q0064726F707341726553652Q746C6564026Q00F03F029A5Q99B93F023E3Q0012F4000200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200073Q00122Q000300086Q000400016Q00020004000200062Q0002001000010001000437012Q001000012Q00AF00026Q00FF000200023Q0012EB000200094Q002301020001000200203600020002000A0012EB0003000B4Q0084010400014Q000600030002000200061E0103003900013Q000437012Q003900010012EB000300094Q00230103000100020006340003003900010002000437012Q003900010012EB0003000C4Q008401046Q00060003000200022Q00A7000400033Q000E790104002900010004000437012Q002900010012EB0004000D4Q0084010500034Q000600040002000200061E0104003000013Q000437012Q003000012Q00FF000300023Q000437012Q003000010012EB000400094Q002301040001000200205B00050002000E0006340005003000010004000437012Q003000012Q00AF00046Q00FF000400023Q0012EB000400073Q0012430005000F4Q0084010600014Q003F0104000600020006F20004001300010001000437012Q001300012Q00AF00046Q00FF000400023Q000437012Q001300010012EB0003000C4Q008401046Q0089000300044Q001001036Q00583Q00017Q00023Q0003053Q0073746F6E65030D3Q006765744E6F646543656E746572030C3Q0026392Q01000A00010001000437012Q000A000100061E012Q000A00013Q000437012Q000A00010012EB000300024Q008401046Q000600030002000200061E0103000A00013Q000437012Q000A00012Q00FF000300024Q00FF000200024Q00583Q00017Q00243Q0003093Q006661726D506861736503043Q006D696E6503113Q0063752Q72656E745461726765745061727403063Q00506172656E7403063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030F3Q0067657450617274506F736974696F6E03103Q006765744D696E65416E63686F72506F73030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403183Q0067657454656C65706F7274486569676874466F724B696E6403013Q0059030C3Q004F72626974456E61626C6564030A3Q006F72626974416E676C65030A3Q004F7262697453702Q6564026Q11913F030D3Q004F726269744469616D65746572027Q004003073Q00566563746F72332Q033Q006E657703013Q005803043Q006D6174682Q033Q00636F7303013Q005A2Q033Q0073696E030B3Q0041696D417454617267657403053Q0073746F6E6503063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747903083Q00557365436C69636B030F3Q0067657441696D5363722Q656E506F73030B3Q00686F6C644D6F757365417400743Q0012EB3Q00013Q0026BF3Q000400010002000437012Q000400012Q00583Q00013Q0012EB3Q00033Q00061E012Q000B00013Q000437012Q000B00010012EB3Q00033Q002008014Q00040006F23Q000C00010001000437012Q000C00012Q00583Q00013Q0012EB3Q00053Q002008014Q000600061E012Q001500013Q000437012Q001500010012EB3Q00053Q002008014Q00060020BC5Q0007001243000200084Q003F012Q000200020006F23Q001800010001000437012Q001800012Q00583Q00013Q0012EB000100093Q0012EB000200034Q00060001000200020006F20001001E00010001000437012Q001E00012Q00583Q00013Q0012EB0002000A3Q0012030003000B3Q00122Q0004000C6Q000500016Q00020005000200122Q0003000D3Q00122Q0004000C6Q00030002000200202Q00040002000E4Q0004000400034Q000500053Q00122Q0006000F3Q00062Q0006004700013Q000437012Q004700010012EB000600103Q0012AB000700113Q00202Q0007000700124Q00060006000700122Q000600103Q00122Q000600133Q00202Q00060006001400122Q000700153Q00202Q00070007001600202Q00080002001700122Q000900183Q00202Q00090009001900122Q000A00106Q0009000200024Q0009000900064Q0008000800094Q000900043Q00202Q000A0002001A00122Q000B00183Q00202Q000B000B001B00122Q000C00106Q000B000200024Q000B000B00064Q000A000A000B4Q0007000A00024Q000500073Q00044Q004E00010012EB000600153Q00200B01060006001600202Q0007000200174Q000800043Q00202Q00090002001A4Q0006000900024Q000500063Q0012EB0006001C3Q00061E0106005B00013Q000437012Q005B00010012EB0006000C3Q0026BF0006005B0001001D000437012Q005B00010012EB0006001E3Q00206A0106000600164Q000700056Q000800016Q00060008000200104Q001E000600044Q006000010012EB0006001E3Q0020080106000600162Q0084010700054Q000600060002000200101C3Q001E00060012EB000600153Q00205101060006002000104Q001F000600122Q000600153Q00202Q00060006002000104Q0021000600122Q000600223Q00062Q0006007300010001000437012Q007300010012EB000600033Q00061E0106007300013Q000437012Q007300010012EB000600233Q001276010700036Q00060002000700122Q000800246Q000900066Q000A00076Q0008000A00012Q00583Q00017Q00023Q00030C3Q007363722Q656E477569526566030E3Q00497344657363656E64616E744F66010E3Q0012EB000100013Q00061E2Q01000C00013Q000437012Q000C00010012EB000100013Q00062A3Q000B00010001000437012Q000B00010020BC00013Q00020012EB000300014Q003F2Q0100030002000437012Q000C00012Q001B00016Q00D3000100014Q00FF000100024Q00583Q00017Q00073Q0003063Q00737472696E6703053Q006C6F77657203043Q004E616D6503063Q00697061697273030B3Q0054524144455F48494E545303043Q0066696E64026Q00F03F01183Q00127F000100013Q00202Q00010001000200202Q00023Q00034Q00010002000200122Q000200043Q00122Q000300056Q00020002000400044Q001300010012EB000700013Q0020C30007000700064Q000800016Q000900063Q00122Q000A00076Q000B00016Q0007000B000200062Q0007001300013Q000437012Q001300012Q00D3000700014Q00FF000700023Q00067C0102000800010002000437012Q000800012Q00D300026Q00FF000200024Q00583Q00017Q00083Q0003083Q0069734F75724775692Q033Q0049734103093Q005363722Q656E47756903073Q00456E61626C6564010003093Q004775694F626A65637403073Q0056697369626C6503063Q0041637469766501153Q0012EB000100014Q008401026Q000600010002000200061E2Q01000600013Q000437012Q000600012Q00583Q00013Q0020BC00013Q0002001243000300034Q003F2Q010003000200061E2Q01000D00013Q000437012Q000D0001003019012Q00040005000437012Q001400010020BC00013Q0002001243000300064Q003F2Q010003000200061E2Q01001400013Q000437012Q00140001003019012Q00070005003019012Q000800052Q00583Q00017Q00053Q00030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A65637403063Q00697061697273030E3Q0047657444657363656E64616E7473011E3Q0012EB000100013Q00061E2Q01000500013Q000437012Q000500010006F23Q000600010001000437012Q000600012Q00583Q00013Q0012EB000100024Q008401026Q000600010002000200061E2Q01000E00013Q000437012Q000E00010012EB000100034Q008401026Q00310001000200010012EB000100043Q0020BC00023Q00052Q002E000200034Q00EE00013Q0003000437012Q001B00010012EB000600024Q0084010700054Q000600060002000200061E0106001B00013Q000437012Q001B00010012EB000600034Q0084010700054Q003100060002000100067C2Q01001300010002000437012Q001300012Q00583Q00017Q000B3Q0003113Q00426C6F636B5569447572696E674661726D03063Q0069706169727303093Q00706C61796572477569030B3Q004765744368696C6472656E2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F757247756903073Q00456E61626C6564030A3Q0068692Q64656E477569733Q012Q001D3Q0012EB3Q00013Q0006F23Q000400010001000437012Q000400012Q00583Q00013Q0012EB3Q00023Q0012672Q0100033Q00202Q0001000100044Q000100029Q00000200044Q001A00010020BC000500040005001243000700064Q003F01050007000200061E0105001A00013Q000437012Q001A00010012EB000500074Q0084010600044Q00060005000200020006F20005001A00010001000437012Q001A000100200801050004000800061E0105001A00013Q000437012Q001A00010012EB000500093Q00200500050004000A00301901040008000B00067C012Q000A00010002000437012Q000A00012Q00583Q00017Q00023Q0003053Q0070616972730001083Q0012EB000100014Q008401026Q00FC000100020003000437012Q000500010020053Q0004000200067C2Q01000400010001000437012Q000400012Q00583Q00017Q000A3Q0003053Q00706169727303133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q007063612Q6C030A3Q00636C6561725461626C65030A3Q0068692Q64656E4775697303063Q00506172656E742Q0103043Q006E65787403043Q007461736B03053Q006465666572002B3Q0012EB3Q00013Q0012EB000100024Q00FC3Q00020002000437012Q000B000100061E0104000A00013Q000437012Q000A00010012EB000500033Q00067501063Q000100012Q0084012Q00044Q00310005000200012Q00F600035Q00067C012Q000400010002000437012Q000400010012EB3Q00043Q0012A3000100028Q000200019Q0000122Q000100013Q00122Q000200056Q00010002000300044Q001B000100200801060004000600061E0106001B00013Q000437012Q001B000100061E0105001B00013Q000437012Q001B00010020053Q0004000700067C2Q01001500010002000437012Q001500010012EB000100043Q00125D010200056Q00010002000100122Q000100086Q00028Q00010002000200062Q0001002A00013Q000437012Q002A00010012EB000100093Q0020082Q010001000A00067501020001000100012Q0084017Q00310001000200012Q00583Q00013Q00023Q00013Q00030A3Q00446973636F2Q6E65637400044Q00387Q0020BC5Q00012Q00313Q000200012Q00583Q00017Q00043Q0003053Q00706169727303063Q00506172656E7403073Q00456E61626C65642Q01000B3Q0012EB3Q00014Q003800016Q00FC3Q00020002000437012Q0008000100200801040003000200061E0104000800013Q000437012Q0008000100301901030003000400067C012Q000400010001000437012Q000400012Q00583Q00017Q000A3Q00030C3Q0073746F70536166654D6F6465030D3Q00686964654F7468657247756973030A3Q007363616E54726164657303093Q00706C6179657247756903133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q006368696C64030A3Q004368696C64412Q64656403073Q00436F2Q6E65637403043Q0064657363030F3Q0044657363656E64616E74412Q64656400163Q001258012Q00018Q0001000100124Q00028Q0001000100124Q00033Q00122Q000100048Q0002000100124Q00053Q00122Q000100043Q00202Q00010001000700202Q00010001000800027200036Q000C2Q010003000200104Q0006000100124Q00053Q00122Q000100043Q00202Q00010001000A00202Q000100010008000272000300014Q003F2Q010003000200101C3Q000900012Q00583Q00013Q00023Q00033Q00030B3Q004661726D456E61626C656403043Q007461736B03053Q006465666572010A3Q0012EB000100013Q0006F20001000400010001000437012Q000400012Q00583Q00013Q0012EB000100023Q0020082Q010001000300067501023Q000100012Q0084017Q00310001000200012Q00583Q00013Q00013Q00093Q0003113Q00426C6F636B5569447572696E674661726D2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F7572477569030A3Q0068692Q64656E477569732Q0103073Q00456E61626C65640100030A3Q007363616E54726164657300173Q0012EB3Q00013Q00061E012Q001300013Q000437012Q001300012Q00387Q0020BC5Q0002001243000200034Q003F012Q0002000200061E012Q001300013Q000437012Q001300010012EB3Q00044Q003800016Q00063Q000200020006F23Q001300010001000437012Q001300010012EB3Q00054Q003800015Q0020053Q000100062Q00387Q003019012Q000700080012EB3Q00094Q003800016Q00313Q000200012Q00583Q00017Q00053Q00030B3Q004661726D456E61626C6564030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B65547261646503043Q007461736B03053Q00646566657201123Q0012EB000100013Q00061E2Q01000600013Q000437012Q000600010012EB000100023Q0006F20001000700010001000437012Q000700012Q00583Q00013Q0012EB000100034Q008401026Q000600010002000200061E2Q01001100013Q000437012Q001100010012EB000100043Q0020082Q010001000500067501023Q000100012Q0084017Q00310001000200012Q00583Q00013Q00013Q00013Q00030F3Q006869646554726164654F626A65637400043Q0012EB3Q00014Q003800016Q00313Q000200012Q00583Q00017Q00043Q0003063Q00706C61796572030E3Q0046696E6446697273744368696C6403043Q004461746103093Q005265736F7572636573000D3Q0012403Q00013Q00206Q000200122Q000200038Q0002000200064Q000800010001000437012Q000800012Q00AE000100014Q00FF000100023Q0020BC00013Q0002001243000300044Q0089000100034Q00102Q016Q00583Q00017Q00073Q0003123Q006765745265736F7572636573466F6C646572028Q00030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565011A3Q0012EB000100014Q00232Q01000100020006F20001000600010001000437012Q00060001001243000200024Q00FF000200023Q0020BC0002000100032Q008401046Q003F01020004000200061E0102001700013Q000437012Q001700010020BC000300020004001243000500054Q003F0103000500020006F20003001500010001000437012Q001500010020BC000300020004001243000500064Q003F01030005000200061E0103001700013Q000437012Q001700010020080103000200072Q00FF000300023Q001243000300024Q00FF000300024Q00583Q00017Q00053Q00028Q0003073Q00436F636F6E757403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7400133Q00128C3Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300046Q00020002000400044Q000D00010012EB000700054Q0084010800064Q00060007000200020006343Q000D00010007000437012Q000D00012Q0084012Q00074Q00842Q0100063Q00067C0102000600010002000437012Q000600012Q008401026Q0084010300014Q0071000200034Q00583Q00017Q00053Q00030F3Q004175746F53652Q6C456E61626C656403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7403143Q0053652Q6C436F636F6E75745468726573686F6C6400163Q0012EB3Q00013Q0006F23Q000500010001000437012Q000500012Q00D38Q00FF3Q00023Q0012EB3Q00023Q0012EB000100034Q00FC3Q00020002000437012Q001100010012EB000500044Q0084010600044Q00060005000200020012EB000600053Q0006340006001100010005000437012Q001100012Q00D3000500014Q00FF000500023Q00067C012Q000900010002000437012Q000900012Q00D38Q00FF3Q00024Q00583Q00017Q00073Q00030D3Q006661726D54696D65546F74616C030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q0003043Q007469636B03043Q006D61746803053Q00666C2Q6F7200123Q0012EB3Q00013Q0012EB000100023Q00061E2Q01000C00013Q000437012Q000C00010012EB000100033Q000E790104000C00010001000437012Q000C00010012EB000100054Q00232Q01000100020012EB000200034Q00490001000100022Q0016014Q00010012EB000100063Q0020350001000100074Q00028Q000100026Q00019Q0000017Q00073Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E2Q033Q0073796E03043Q00682Q7470030B3Q00482Q747053657276696365030C3Q00526571756573744173796E63013A3Q00027200015Q0012EB000200013Q0012EB000300024Q00060002000200020026390102000D00010003000437012Q000D00012Q0084010200013Q00067501030001000100012Q0084017Q000600020002000200061E0102000D00013Q000437012Q000D00012Q00FF000200023Q0012EB000200043Q00061E0102001B00013Q000437012Q001B00010012EB000200043Q00200801020002000200061E0102001B00013Q000437012Q001B00012Q0084010200013Q00067501030002000100012Q0084017Q000600020002000200061E0102001B00013Q000437012Q001B00012Q00FF000200023Q0012EB000200053Q00061E0102002900013Q000437012Q002900010012EB000200053Q00200801020002000200061E0102002900013Q000437012Q002900012Q0084010200013Q00067501030003000100012Q0084017Q000600020002000200061E0102002900013Q000437012Q002900012Q00FF000200023Q0012EB000200063Q00061E0102003700013Q000437012Q003700010012EB000200063Q00200801020002000700061E0102003700013Q000437012Q003700012Q0084010200013Q00067501030004000100012Q0084017Q000600020002000200061E0102003700013Q000437012Q003700012Q00FF000200024Q00AE000200024Q00FF000200024Q00583Q00013Q00053Q00013Q0003053Q007063612Q6C01093Q0012EB000100014Q008401026Q00FC00010002000200061E2Q01000600013Q000437012Q000600012Q00FF000200024Q00AE000300034Q00FF000300024Q00583Q00017Q00013Q0003073Q007265717565737400053Q0012413Q00016Q00019Q0000019Q008Q00017Q00023Q002Q033Q0073796E03073Q007265717565737400063Q001269012Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00023Q0003043Q00682Q747003073Q007265717565737400063Q001269012Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00073Q00030B3Q00482Q747053657276696365030C3Q00526571756573744173796E632Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q004865616465727303043Q00426F647900153Q00126E3Q00013Q00206Q00024Q00023Q00044Q00035Q00202Q00030003000300102Q0002000300034Q00035Q00202Q00030003000400062Q0003000B00010001000437012Q000B0001001243000300053Q00101C0002000400032Q001A00035Q00202Q00030003000600102Q0002000600034Q00035Q00202Q00030003000700102Q0002000700036Q00029Q008Q00017Q001F3Q0003043Q006773756203043Q005E25732B034Q0003043Q0025732B2403143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B9030B3Q00682Q7470526571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030A3Q00537461747573436F646503063Q0073746174757303063Q0053746174757303083Q00746F6E756D626572026Q006940025Q00C0724003143Q00D09ED182D0BFD180D0B0D0B2D0BBD0B5D0BDD0BE03053Q00482Q54502003083Q00746F737472696E6703073Q0053752Q63652Q733Q010003113Q00482Q545020D0BED188D0B8D0B1D0BAD0B003053Q007063612Q6C031D3Q00D09ED188D0B8D0B1D0BAD0B020D0BED182D0BFD180D0B0D0B2D0BAD0B82Q033Q00737562026Q00F03F026Q005840025D3Q00206301023Q000100122Q000400023Q00122Q000500036Q00020005000200202Q00020002000100122Q000400043Q00122Q000500036Q0002000500026Q00023Q00264Q000E00010003000437012Q000E00012Q00D300025Q001243000300054Q0071000200033Q0012EB000200064Q007B00033Q000400102Q000300073Q00302Q0003000800094Q00043Q000100302Q0004000B000C00102Q0003000A000400102Q0003000D00014Q00020002000200062Q0002004700013Q000437012Q0047000100200801030002000E0006F20003002000010001000437012Q0020000100200801030002000F0006F20003002000010001000437012Q0020000100200801030002001000061E0103003800013Q000437012Q003800010012EB000400114Q0084010500034Q000600040002000200061E0104003800013Q000437012Q003800010012EB000400114Q0084010500034Q0006000400020002000E2A0112003100010004000437012Q003100010026230004003100010013000437012Q003100012Q00D3000500013Q001243000600144Q0071000500034Q00D300055Q001210000600153Q00122Q000700166Q000800036Q0007000200024Q0006000600074Q000500033Q0020080104000200170026390104003E00010018000437012Q003E00012Q00D3000400013Q001243000500144Q0071000400033Q0020080104000200170026390104004400010019000437012Q004400012Q00D300045Q0012430005001A4Q0071000400034Q00D3000400013Q001243000500144Q0071000400033Q0012EB0003001B3Q00067501043Q000100022Q0084017Q0084012Q00014Q00FC00030002000400061E0103005100013Q000437012Q005100012Q00D3000500013Q001243000600144Q0071000500034Q00D300055Q0012EB000600163Q0006140107005600010004000437012Q005600010012430007001C4Q000600060002000200203C00060006001D00122Q0008001E3Q00122Q0009001F6Q000600096Q00059Q0000013Q00013Q00053Q00030B3Q00482Q74705365727669636503093Q00506F73744173796E6303043Q00456E756D030F3Q00482Q7470436F6E74656E7454797065030F3Q00412Q706C69636174696F6E4A736F6E000A3Q001228012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400033Q00202Q00040004000400202Q0004000400054Q00059Q00000500016Q00017Q001F3Q00034Q0003143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B903043Q006E616D65030A3Q00D098D0B3D180D0BED0BA03053Q0076616C756503063Q00706C6179657203043Q004E616D652Q033Q0020286003083Q00746F737472696E6703063Q0055736572496403023Q00602903063Q00696E6C696E65010003063Q0069706169727303053Q007461626C6503063Q00696E73657274030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646503063Q00656D6265647303053Q007469746C6503053Q00636F6C6F72023Q00806D4C4A4103063Q006669656C647303063Q00662Q6F74657203043Q007465787403083Q004D4158492048554203093Q0074696D657374616D7003083Q004461746554696D652Q033Q006E6F7703093Q00546F49736F4461746503123Q00706F7374446973636F7264576562682Q6F6B04403Q00061E012Q000400013Q000437012Q00040001002639012Q000700010001000437012Q000700012Q00D300045Q001243000500024Q0071000400034Q00AF000400014Q004D01053Q000300302Q00050003000400122Q000600063Q00202Q00060006000700122Q000700083Q00122Q000800093Q00122Q000900063Q00202Q00090009000A4Q00080002000200122Q0009000B6Q00060006000900102Q00050005000600302Q0005000C000D4Q00040001000100061E0103002300013Q000437012Q002300010012EB0005000E4Q0084010600034Q00FC000500020007000437012Q002100010012EB000A000F3Q002008010A000A00102Q0084010B00044Q0084010C00094Q0040010A000C000100067C0105001C00010002000437012Q001C00010012EB000500113Q0020330105000500124Q00073Q00014Q000800016Q00093Q000500102Q00090014000100062Q000A002C00010002000437012Q002C0001001243000A00163Q00101C00090015000A00100A0109001700044Q000A3Q000100302Q000A0019001A00102Q00090018000A00122Q000A001C3Q00202Q000A000A001D4Q000A0001000200202Q000A000A001E4Q000A0002000200102Q0009001B000A2Q00A500080001000100101C0007001300082Q002400050007000200122Q0006001F6Q00078Q000800056Q000600086Q00069Q0000017Q00193Q0003123Q006765745265736F7572636573466F6C6465722Q033Q00E2809403063Q00697061697273030B3Q004765744368696C6472656E2Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565026Q00F03F03053Q007461626C6503063Q00696E7365727403043Q006E616D6503043Q004E616D652Q033Q0076616C03043Q00736F727403023Q003A2003083Q00746F737472696E6703063Q00636F6E63617403013Q000A025Q00408F4003063Q00737472696E672Q033Q00737562025Q00288F402Q033Q003Q2E029Q00523Q0012EB3Q00014Q0023012Q000100020006F23Q000600010001000437012Q00060001001243000100024Q00FF000100024Q00AF00015Q001267010200033Q00202Q00033Q00044Q000300046Q00023Q000400044Q002200010020BC000700060005001243000900064Q003F0107000900020006F20007001600010001000437012Q001600010020BC000700060005001243000900074Q003F01070009000200061E0107002200013Q000437012Q00220001002008010700060008000E790109002200010007000437012Q002200010012EB0007000A3Q00204801070007000B4Q000800016Q00093Q000200202Q000A0006000D00102Q0009000C000A00202Q000A0006000800102Q0009000E000A4Q00070009000100067C0102000C00010002000437012Q000C00010012EB0002000A3Q00200801020002000F2Q0084010300013Q00027200046Q00260102000400014Q00025Q00122Q000300036Q000400016Q00030002000500044Q003800010012EB0008000A3Q0020B800080008000B4Q000900023Q00202Q000A0007000C00122Q000B00103Q00122Q000C00113Q00202Q000D0007000E4Q000C000200024Q000A000A000C4Q0008000A000100067C0103002E00010002000437012Q002E00010012EB0003000A3Q0020C00003000300124Q000400023Q00122Q000500136Q0003000500024Q000400033Q000E2Q0014004A00010004000437012Q004A00010012EB000400153Q0020710104000400164Q000500033Q00122Q000600093Q00122Q000700176Q00040007000200122Q000500186Q0003000400052Q00A7000400023Q000E790119004F00010004000437012Q004F00010006140104005000010003000437012Q00500001001243000400024Q00FF000400024Q00583Q00013Q00013Q00013Q002Q033Q0076616C02083Q00200801023Q000100200801030001000100061F0103000500010002000437012Q000500012Q001B00026Q00D3000200014Q00FF000200024Q00583Q00017Q001C3Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D617403093Q002564D0BC202564D18103023Q00D18103043Q006E616D65031D3Q00D0A1D180D183D0B1D0B8D0BB20D0B4D0B5D180D0B5D0B2D18CD0B5D0B203053Q0076616C756503083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q00696E6C696E652Q0103193Q00D0A1D180D183D0B1D0B8D0BB20D0BAD0B0D0BCD0BDD0B5D0B903123Q0073652Q73696F6E53746F6E65734D696E6564031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0B4D0B5D1802E2903103Q0073652Q73696F6E54722Q6544726F7073031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0BAD0B0D0BC2E2903113Q0073652Q73696F6E53746F6E6544726F707303153Q00D092D180D0B5D0BCD18F20D184D0B0D180D0BCD0B0030A3Q00D0A0D0B5D0B6D0B8D0BC030F3Q006765744661726D4D6F646554657874030E3Q005265736F757263657320283E312903173Q006765745265736F75726365734F7665724F6E6554657874012Q00453Q001285012Q00018Q0001000200122Q000100023Q00202Q00010001000300202Q00023Q00044Q00010002000200202Q00023Q00044Q000300033Q000E2Q0005001200010001000437012Q001200010012EB000400063Q0020B300040004000700122Q000500086Q000600016Q000700026Q0004000700024Q000300043Q00044Q001500012Q008401045Q001243000500094Q00F80003000400052Q00AF000400074Q000901053Q000300302Q0005000A000B00122Q0006000D3Q00122Q0007000E6Q00060002000200102Q0005000C000600302Q0005000F00104Q00063Q000300302Q0006000A001100122Q0007000D3Q0012EB000800124Q00D900070002000200102Q0006000C000700302Q0006000F00104Q00073Q000300302Q0007000A001300122Q0008000D3Q00122Q000900146Q00080002000200102Q0007000C000800302Q0007000F00102Q00AF00083Q000300300D0108000A001500122Q0009000D3Q00122Q000A00166Q00090002000200102Q0008000C000900302Q0008000F00104Q00093Q000300302Q0009000A001700102Q0009000C000300302Q0009000F00102Q00AF000A3Q000300302F010A000A001800122Q000B00196Q000B0001000200102Q000A000C000B00302Q000A000F00104Q000B3Q000300302Q000B000A001A00122Q000C001B6Q000C0001000200102Q000B000C000C003019010B000F001C2Q00A50004000700012Q00FF000400024Q00583Q00017Q00083Q0003153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003063Q0069706169727303153Q0067657453652Q73696F6E53746174734669656C647303053Q007461626C6503063Q00696E7365727403103Q0073656E64446973636F7264456D626564021F3Q0012EB000200013Q0006F20002000400010001000437012Q000400012Q00583Q00013Q0012EB000200024Q002301020001000200061E0102000A00013Q000437012Q000A00010026390102000B00010003000437012Q000B00012Q00583Q00014Q00AF00035Q001254000400043Q00122Q000500056Q000500016Q00043Q000600044Q001600010012EB000900063Q0020080109000900072Q0084010A00034Q0084010B00084Q00400109000B000100067C0104001100010002000437012Q001100010012EB000400084Q00E9000500026Q00068Q000700016Q000800036Q0004000800016Q00017Q00093Q0003043Q007469636B026Q00284003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403043Q007461736B03043Q0077616974029A5Q99B93F011C3Q0012EB000100014Q00232Q01000100020006140102000500013Q000437012Q00050001001243000200024Q00162Q01000100020012EB000200014Q00230102000100020006340002001900010001000437012Q001900010012EB000200033Q00200801020002000400065E0003001100010002000437012Q001100010020BC000300020005001243000500064Q003F01030005000200061E0103001400013Q000437012Q001400012Q00FF000300023Q0012EB000400073Q002008010400040008001243000500094Q0031000400020001000437012Q000600012Q00AE000200024Q00FF000200024Q00583Q00017Q00053Q0003053Q00666F72636503043Q007461736B03043Q007761697403113Q00696E74652Q7275707469626C655761697403053Q0072756E496402133Q00061E2Q01000B00013Q000437012Q000B000100200801020001000100061E0102000B00013Q000437012Q000B00010012EB000200023Q0020410102000200034Q00038Q0002000200014Q000200016Q000200023Q0012EB000200044Q008401035Q00065E0004001000010001000437012Q001000010020080104000100052Q0089000200044Q001001026Q00583Q00017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E40030E3Q0053652Q6C4974656D52656D6F7465000F3Q00125C3Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q000900010001000437012Q000900012Q00AE000100014Q00FF000100023Q0020BC00013Q00020012B0000300053Q00122Q000400046Q000100046Q00019Q0000017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E4003133Q00576F726C6454656C65706F727452656D6F7465000F3Q00125C3Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q000900010001000437012Q000900012Q00AE000100014Q00FF000100023Q0020BC00013Q00020012B0000300053Q00122Q000400046Q000100046Q00019Q0000017Q00023Q0003163Q00676574576F726C6454656C65706F727452656D6F746503053Q007063612Q6C010D3Q0012EB000100014Q00232Q01000100020006F20001000600010001000437012Q000600012Q00D300026Q00FF000200023Q0012EB000200023Q00067501033Q000100022Q0084017Q0084012Q00014Q00060002000200022Q00FF000200024Q00583Q00013Q00013Q00053Q00026Q00F03F027Q0040030C3Q00496E766F6B6553657276657203053Q007461626C6503063Q00756E7061636B000D4Q00505Q00024Q00015Q00104Q000100014Q00015Q00104Q000200014Q000100013Q00202Q00010001000300122Q000300043Q00202Q0003000300054Q00048Q000300046Q00013Q00016Q00017Q00023Q00030D3Q0067657453652Q6C52656D6F746503053Q007063612Q6C010D3Q0012EB000100014Q00232Q01000100020006F20001000600010001000437012Q000600012Q00D300026Q00FF000200023Q0012EB000200023Q00067501033Q000100022Q0084017Q0084012Q00014Q00060002000200022Q00FF000200024Q00583Q00013Q00013Q00073Q00026Q00F03F03083Q004974656D4E616D6503063Q00416D6F756E74030F3Q0053652Q6C4261746368416D6F756E74030A3Q004669726553657276657203053Q007461626C6503063Q00756E7061636B000F4Q00045Q00014Q00013Q00024Q00025Q00102Q00010002000200122Q000200043Q00102Q00010003000200104Q000100014Q000100013Q00202Q00010001000500122Q000300063Q00202Q0003000300074Q00048Q000300046Q00013Q00016Q00017Q002C3Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003053Q00666F726365030F3Q004175746F53652Q6C456E61626C6564030D3Q006E2Q6564734175746F53652Q6C03093Q006661726D506861736503043Q0073652Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03103Q00636C6561724661726D5761726E696E6703093Q0073652Q6C5F6661696C030D3Q007361766553652Q6C537461746503063Q006D616E75616C2Q01030A3Q00726573756D654661726D031B3Q00D0A2D09F20D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D1833Q2E030D3Q00776F726C6454656C65706F7274030D3Q0053452Q4C5F574F524C445F4944030E3Q00636C65617253652Q6C5374617465030F3Q00707573684661726D5761726E696E6703383Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D182D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18303043Q0069646C6503363Q00D0A2D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18320D0BDD0B520D183D0B4D0B0D0BBD181D18F03253Q00D096D0B4D191D0BC20D0B7D0B0D0B3D180D183D0B7D0BAD18320D0BCD0B8D180D0B03Q2E03133Q0077616974466F72436861726163746572487270026Q00284003123Q0053452Q4C5F574149545F41465445525F5450031F3Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0B5D180D0B2D0B0D0BDD0B0030D3Q006C6F616453652Q6C537461746503053Q00706861736503493Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0BED0B4D0BED0BBD0B6D0B8D182D181D18F20D0BFD0BED181D0BBD0B520D0BFD0B5D180D0B5D0B7D0B0D0B3D180D183D0B7D0BAD0B803203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D7303233Q0053652Q6C4974656D52656D6F746520D0BDD0B5D0B4D0BED181D182D183D0BFD0B5D0BD026Q00F03F03063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q004641524D5F574F524C445F494403343Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0B2D0B5D180D0BDD183D182D18CD181D18F20D0BDD0B020D184D0B0D180D0BC027Q004003123Q0066696E616C697A6553652Q6C526573756D6503323Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD180D0BED0B4D0B0D182D18C2028D0BDD0B5D1822072656D6F74652903213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B002CC3Q0006F20001000400010001000437012Q000400012Q00AF00026Q00842Q0100023Q0012EB000200013Q00061E0102000A00013Q000437012Q000A00012Q00D300025Q001243000300024Q0071000200033Q0020080102000100030006F20002001800010001000437012Q001800010012EB000200043Q0006F20002001200010001000437012Q001200012Q00D300026Q00FF000200023Q0012EB000200054Q00230102000100020006F20002001800010001000437012Q001800012Q00D300026Q00FF000200023Q00067501023Q000100012Q0084012Q00013Q00067501030001000100022Q0084012Q00014Q0084016Q00067501040002000100022Q0084012Q00014Q0084017Q009E000500013Q00122Q000500013Q00122Q000500073Q00122Q000500063Q00122Q000500086Q00050001000100122Q000500096Q00050001000100122Q0005000A6Q00050001000100122Q0005000B3Q00122Q0006000C6Q00050002000100122Q0005000D3Q00122Q000600076Q00073Q000200202Q00080001000300262Q000800340001000F000437012Q003400012Q001B00086Q00D3000800013Q00101C0007000E00080020080108000100100026BF0008003A0001000F000437012Q003A00012Q001B00086Q00D3000800013Q0010A20007001000084Q0005000700014Q000500023Q00122Q000600116Q00050002000100122Q000500123Q00122Q000600136Q00050002000200062Q0005005200010001000437012Q005200010012EB000500144Q003101050001000100122Q000500153Q00122Q0006000C3Q00122Q000700166Q0005000700014Q00055Q001256010500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q000600186Q000500034Q0084010500023Q00124A000600196Q00050002000100122Q0005001A3Q00122Q0006001B6Q0005000200012Q0084010500033Q0012EB0006001C4Q00060005000200020006F20005006600010001000437012Q006600010012EB000500144Q00060105000100014Q00055Q00122Q000500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q0006001D6Q000500033Q0012EB0005001E4Q002301050001000200061E0105006D00013Q000437012Q006D000100200801060005001F0026BF0006007400010007000437012Q007400012Q00D300065Q001256010600013Q00122Q000600173Q00122Q000600066Q000600013Q00122Q000700206Q000600034Q0084010600023Q00122D010700216Q00060002000100122Q000600226Q000700036Q000800046Q00060008000200062Q0006008100010001000437012Q008100010012EB000700153Q0012430008000C3Q001243000900234Q00400107000900012Q0084010700033Q001243000800244Q00060007000200020006F20007008F00010001000437012Q008F00010012EB000700144Q00060107000100014Q00075Q00122Q000700013Q00122Q000700173Q00122Q000700066Q00075Q00122Q0008001D6Q000700033Q0012EB0007000D3Q001243000800254Q00AF00093Q0002002008010A000100030026BF000A00960001000F000437012Q009600012Q001B000A6Q00D3000A00013Q00101C0009000E000A002008010A000100100026BF000A009C0001000F000437012Q009C00012Q001B000A6Q00D3000A00013Q0010A200090010000A4Q0007000900014Q000700023Q00122Q000800266Q00070002000100122Q000700123Q00122Q000800276Q00070002000200062Q000700AB00010001000437012Q00AB00010012EB000700153Q0012430008000C3Q001243000900284Q00400107000900010012EB0007001A3Q0012BA0008001B6Q0007000200014Q000700033Q00122Q000800296Q00070002000100122Q0007001E6Q00070001000200062Q000700BC00013Q000437012Q00BC000100200801080007001F002639010800BC00010025000437012Q00BC00010012EB0008002A4Q0084010900014Q0084010A00064Q00400108000A00012Q00D300085Q0012CB000800013Q00122Q000800173Q00122Q000800063Q00122Q0008000B3Q00122Q0009000C6Q00080002000100062Q000600C800010001000437012Q00C800012Q00D300085Q0012430009002B4Q0071000800034Q00D3000800013Q0012430009002C4Q0071000800034Q00583Q00013Q00033Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q003800015Q0020082Q010001000100061E2Q01000900013Q000437012Q000900010012EB000100024Q003800025Q0020080102000200012Q008401036Q00402Q01000300012Q00583Q00017Q00033Q0003083Q0073652Q6C5761697403053Q00666F72636503053Q0072756E4964010B3Q0012472Q0100016Q00028Q00033Q00024Q00045Q00202Q00040004000200102Q0003000200044Q000400013Q00102Q0003000300044Q000100036Q00016Q00583Q00017Q00033Q0003053Q00666F726365030E3Q0073652Q6C496E50726F6772652Q7303123Q0073686F756C644661726D436F6E74696E7565000B4Q00387Q002008014Q000100061E012Q000600013Q000437012Q000600010012EB3Q00024Q00FF3Q00023Q0012EB3Q00034Q0038000100014Q00893Q00014Q0010017Q00583Q00017Q00053Q00030C3Q0072756E53652Q6C4379636C6503053Q00666F7263650100030A3Q00726573756D654661726D3Q01073Q0012E8000100016Q00028Q00033Q000200302Q00030002000300302Q0003000400054Q0001000300016Q00017Q00043Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003043Q007461736B03053Q00737061776E01103Q0012EB000100013Q00061E2Q01000A00013Q000437012Q000A000100061E012Q000900013Q000437012Q000900012Q00842Q016Q00D300025Q001243000300024Q00402Q01000300012Q00583Q00013Q0012EB000100033Q0020082Q010001000400067501023Q000100012Q0084017Q00310001000200012Q00583Q00013Q00013Q000F3Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964026Q00F03F030E3Q006661726D436865636B506175736503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030C3Q0072756E53652Q6C4379636C6503053Q00666F7263652Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303133Q0068617350656E64696E6753652Q6C537461746503093Q0073746172744661726D002E3Q0012EB3Q00013Q00061E012Q000600013Q000437012Q000600010012EB000100023Q00203600010001000300129F000100024Q00D3000100013Q0012722Q0100043Q00122Q000100053Q00122Q000200066Q00010002000100122Q000100053Q00122Q000200076Q00010002000100122Q000100053Q00122Q000200086Q00010002000100122Q000100096Q000200026Q00033Q000300302Q0003000A000B00102Q0003000C3Q00027200045Q00108F0003000D00044Q0001000300024Q00035Q00122Q000300043Q00064Q002600013Q000437012Q002600010012EB000300013Q00061E0103002600013Q000437012Q002600010012EB0003000E4Q00230103000100020006F20003002600010001000437012Q002600010012EB0003000F5Q000103000100012Q003800035Q00061E0103002D00013Q000437012Q002D00012Q003800036Q0084010400014Q0084010500024Q00400103000500012Q00583Q00013Q00013Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q0012EB000100013Q00061E2Q01000900013Q000437012Q000900010012EB000100013Q0020082Q010001000200061E2Q01000900013Q000437012Q000900010012EB000100013Q00101C000100034Q00583Q00017Q00073Q00030F3Q004175746F53652Q6C456E61626C6564030E3Q0073652Q6C496E50726F6772652Q7303043Q007469636B030F3Q006C61737453652Q6C436865636B417403113Q0053652Q6C436865636B496E74657276616C030D3Q006E2Q6564734175746F53652Q6C030B3Q0072756E4175746F53652Q6C01183Q0012EB000100013Q00061E2Q01000600013Q000437012Q000600010012EB000100023Q00061E2Q01000700013Q000437012Q000700012Q00583Q00013Q0012EB000100034Q009900010001000200122Q000200046Q00020001000200122Q000300053Q00062Q0002000F00010003000437012Q000F00012Q00583Q00013Q00129F000100043Q0012EB000200064Q002301020001000200061E0102001700013Q000437012Q001700010012EB000200074Q008401036Q00310002000200012Q00583Q00017Q00073Q00030B3Q004661726D456E61626C656403043Q007469636B03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006C6F674661726D53652Q73696F6E446973636F726403153Q00D09ED182D187D191D18220D184D0B0D180D0BCD0B0023Q00806D4C4A4100123Q0012EB3Q00013Q0006F23Q000400010001000437012Q000400012Q00583Q00013Q0012EB3Q00024Q00993Q0001000200122Q000100036Q00013Q000100122Q000200043Q00062Q0001000C00010002000437012Q000C00012Q00583Q00013Q00129F3Q00033Q00121D2Q0100053Q00122Q000200063Q00122Q000300076Q0001000300016Q00017Q000A3Q0003093Q006661726D506861736503063Q0073656172636803103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403123Q0073686F756C644661726D436F6E74696E756503133Q0072656672657368546172676574436F756E7473030F3Q0067657456616C696454617267657473028Q0003043Q0069646C65030B3Q006875625265737457616974012A3Q00129A000100023Q00122Q000100013Q00122Q000100036Q0001000100014Q000100013Q00122Q000100046Q00015Q0012EB000200054Q008401036Q000600020002000200061E0102002500013Q000437012Q002500010012EB000200064Q009300020001000100122Q000200076Q0002000100024Q000300023Q000E2Q0008001600010003000437012Q00160001001243000300093Q00129F000300014Q00FF000200023Q0012EB000300054Q008401046Q00060003000200020006F20003001C00010001000437012Q001C0001000437012Q002500010012EB0003000A4Q008401046Q0054010500014Q003F0103000500020006F20003002300010001000437012Q00230001000437012Q002500012Q00D3000100013Q000437012Q00070001001243000200093Q00129F000200014Q00AF00026Q00FF000200024Q00583Q00017Q00183Q00030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q00030D3Q006661726D54696D65546F74616C03043Q007469636B03093Q006661726D506861736503043Q0069646C6503093Q006661726D52756E4964026Q00F03F03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030A3Q0072657365744175746F46030C3Q0069676E6F72656444726F707303123Q0074656C65706F7274436F2Q6E656374696F6E030F3Q006D616E75616C53652Q6C546F6B656E030E3Q0073652Q6C496E50726F6772652Q73030A3Q006661726D546872656164030C3Q0073746F70536166654D6F6465003D3Q0012EB3Q00013Q00061E012Q000F00013Q000437012Q000F00010012EB3Q00023Q000E790103000F00013Q000437012Q000F00010012EB3Q00043Q0012422Q0100056Q00010001000200122Q000200026Q0001000100028Q000100124Q00043Q00124Q00033Q00124Q00024Q00D37Q0012953Q00013Q00124Q00073Q00124Q00063Q00124Q00083Q00206Q000900124Q00089Q003Q00124Q000A9Q003Q00124Q000B3Q00124Q000D3Q00124Q000C3Q00124Q000E3Q00122Q0001000F8Q0002000100124Q000E3Q00122Q000100108Q0002000100124Q000E3Q00122Q000100118Q0002000100124Q000E3Q00122Q000100128Q000200019Q0000124Q00133Q00124Q00143Q00064Q003200013Q000437012Q003200010012EB3Q000E3Q00027200016Q00313Q000200012Q00AE7Q00129F3Q00143Q0012EB3Q00153Q0020C45Q000900124Q00159Q003Q00124Q00169Q003Q00124Q00173Q00124Q000E3Q00122Q000100188Q000200016Q00013Q00013Q00023Q0003123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400043Q0012EB3Q00013Q0020BC5Q00022Q00313Q000200012Q00583Q00017Q00013Q00030D3Q006B692Q6C4661726D4C2Q6F707300033Q0012EB3Q00015Q00012Q000100012Q00583Q00017Q00083Q0003083Q0073746F704661726D030C3Q0073746F70536166654D6F6465030E3Q0073746F7043616D6572614C2Q6F7003183Q0064657374726F79426C6F636B65645A6F6E6556697375616C030C3Q007363722Q656E47756952656603063Q00506172656E7403053Q007063612Q6C03093Q007363722Q656E477569001E3Q001222012Q00018Q0001000100124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00053Q00064Q001300013Q000437012Q001300010012EB3Q00053Q002008014Q000600061E012Q001300013Q000437012Q001300010012EB3Q00073Q00027200016Q00313Q00020001000437012Q001D00010012EB3Q00083Q00061E012Q001D00013Q000437012Q001D00010012EB3Q00083Q002008014Q000600061E012Q001D00013Q000437012Q001D00010012EB3Q00073Q000272000100014Q00313Q000200012Q00583Q00013Q00023Q00023Q00030C3Q007363722Q656E47756952656603073Q0044657374726F7900043Q0012EB3Q00013Q0020BC5Q00022Q00313Q000200012Q00583Q00017Q00023Q0003093Q007363722Q656E47756903073Q0044657374726F7900043Q0012EB3Q00013Q0020BC5Q00022Q00313Q000200012Q00583Q00017Q00023Q00030B3Q00736F6674436C65616E7570030D3Q00726573746F726543616D65726100053Q0012EA3Q00018Q0001000100124Q00028Q000100016Q00017Q000E3Q00030D3Q006B692Q6C4661726D4C2Q6F7073030B3Q004661726D456E61626C6564030F3Q006661726D54696D655374617274656403043Q007469636B03103Q006C6173744661726D5265706F7274417403093Q006661726D52756E4964030D3Q007374617274536166654D6F646503123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374030A3Q006661726D54687265616403043Q007461736B03053Q00737061776E001B3Q00122F3Q00018Q000100016Q00013Q00124Q00023Q00124Q00048Q0001000200124Q00033Q00124Q00048Q0001000200124Q00053Q00124Q00063Q00122Q000100076Q00010001000100122Q000100093Q00202Q00010001000A00202Q00010001000B00067501033Q000100012Q0084017Q003F2Q010003000200129F000100083Q0012EB0001000D3Q0020082Q010001000E00067501020001000100012Q0084017Q000600010002000200129F0001000C4Q00583Q00013Q00023Q000B3Q0003123Q0073686F756C644661726D436F6E74696E756503093Q006661726D506861736503073Q00636F2Q6C65637403043Q007761697403043Q0073652Q6C2Q033Q0068756203063Q0073656172636803043Q006D696E6503113Q0063752Q72656E745461726765745061727403053Q007063612Q6C03103Q0074656C65706F7274546F54617267657400203Q0012EB3Q00014Q003800016Q00063Q000200020006F23Q000600010001000437012Q000600012Q00583Q00013Q0012EB3Q00023Q0026BF3Q001500010003000437012Q001500010012EB3Q00023Q0026BF3Q001500010004000437012Q001500010012EB3Q00023Q0026BF3Q001500010005000437012Q001500010012EB3Q00023Q0026BF3Q001500010006000437012Q001500010012EB3Q00023Q002639012Q001600010007000437012Q001600012Q00583Q00013Q0012EB3Q00023Q002639012Q001F00010008000437012Q001F00010012EB3Q00093Q00061E012Q001F00013Q000437012Q001F00010012EB3Q000A3Q0012EB0001000B4Q00313Q000200012Q00583Q00017Q000D3Q0003123Q0073686F756C644661726D436F6E74696E756503053Q007063612Q6C030D3Q00697343616E63656C452Q726F7203043Q007761726E03103Q005B4D415849204855425D206661726D3A03043Q007461736B03043Q0077616974026Q00E03F03093Q006661726D52756E496403113Q0063752Q72656E7454617267657450617274030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0069646C65002E4Q00D37Q0012EB000100014Q003800026Q000600010002000200061E2Q01002200013Q000437012Q002200010012EB000100023Q00067501023Q000100022Q00388Q0084017Q00FC0001000200020006F20001000100010001000437012Q000100010012EB000300034Q0084010400024Q000600030002000200061E0103001300013Q000437012Q00130001000437012Q002200010012EB000300043Q001218010400056Q000500026Q00030005000100122Q000300016Q00048Q00030002000200062Q0003001D00010001000437012Q001D0001000437012Q002200010012EB000300063Q002008010300030007001243000400084Q0031000300020001000437012Q000100012Q003800015Q0012EB000200093Q00067D0001002D00010002000437012Q002D00012Q00AE000100013Q00129F0001000A3Q0012EB0001000B3Q0006F20001002D00010001000437012Q002D00010012430001000D3Q00129F0001000C4Q00583Q00013Q00013Q002F3Q0003103Q006D6179626552756E4175746F53652Q6C03123Q0073686F756C644661726D436F6E74696E756503123Q006D6179626552756E4661726D5265706F727403123Q0063617074757265487562506F736974696F6E030B3Q006875625265737457616974030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473028Q00030E3Q0072756E536561726368506861736503043Q007461736B03043Q0077616974029A5Q99C93F030E3Q007069636B42657374546172676574030A3Q006163746976654E6F646503043Q006E6F646503103Q006163746976655461726765744B696E6403043Q006B696E6403093Q006661726D506861736503043Q006D696E65030A3Q006F72626974416E676C65030A3Q0072657365744175746F46030B3Q00676574486974626F786573030F3Q00707573684661726D5761726E696E6703093Q006E6F5F686974626F7803193Q00D0A320D186D0B5D0BBD0B820D0BDD0B5D18220486974626F78026Q00E03F03103Q00636C6561724661726D5761726E696E6703113Q0063752Q72656E7454617267657450617274026Q00F03F03043Q007469636B026Q004E40030B3Q0069734E6F6465416C697665030B3Q007570646174654175746F46030B3Q006175746F46416374697665030C3Q00737475636B5F6D696E696E67032D3Q00D094D0BED0BBD0B3D0BE20D0BDD0B520D0BBD0BED0BCD0B0D0B5D182D181D18F20E2809420D0B6D0BCD1832046030A3Q00612Q7461636B50617274029A5Q99A93F03103Q0072656C656173654D6F757365486F6C6403053Q0073746F6E6503123Q0073652Q73696F6E53746F6E65734D696E656403113Q0073652Q73696F6E54722Q65734D696E656403103Q0077616974416E645363616E44726F7073030F3Q00636F2Q6C656374412Q6C44726F707303043Q0074722Q6503133Q0073746F704368617261637465724D6F74696F6E03143Q0072657475726E546F48756241667465724E6F646500BA3Q0012563Q00016Q00019Q000002000100124Q00026Q00019Q000002000200064Q000900010001000437012Q000900012Q00583Q00013Q0012EB3Q00034Q00D23Q0001000100124Q00026Q00019Q000002000200064Q001100010001000437012Q001100012Q00583Q00014Q00383Q00013Q0006F23Q001E00010001000437012Q001E00012Q00D33Q00014Q00C93Q00013Q0012EB3Q00044Q00D23Q0001000100124Q00056Q00019Q000002000200064Q001E00010001000437012Q001E00012Q00583Q00013Q0012EB3Q00064Q005C012Q0001000200122Q000100076Q0001000100014Q00015Q00262Q0001003800010008000437012Q003800010012EB000100094Q006B00028Q0001000200026Q00013Q00122Q000100026Q00028Q00010002000200062Q0001003100013Q000437012Q003100012Q00A700015Q0026392Q01003600010008000437012Q003600010012EB0001000A3Q0020082Q010001000B0012430002000C4Q00310001000200012Q00583Q00013Q0012EB000100075Q002Q01000100010012EB0001000D4Q008401026Q00060001000200020006F20001004200010001000437012Q004200010012EB0002000A3Q00200801020002000B0012430003000C4Q00310002000200012Q00583Q00013Q00200801020001000F0012620102000E3Q00202Q00020001001100122Q000200103Q00122Q000200133Q00122Q000200123Q00122Q000200083Q00122Q000200143Q00122Q000200156Q00020001000100122Q000200163Q00122Q0003000E6Q0002000200024Q000300023Q00262Q0003005B00010008000437012Q005B00010012EB000300173Q00122C000400183Q00122Q000500196Q00030005000100122Q0003000A3Q00202Q00030003000B00122Q0004001A6Q0003000200016Q00013Q0012EB0003001B3Q00126A000400186Q00030002000100202Q00030002001D00122Q0003001C3Q00122Q0003001E6Q00030001000200202Q00030003001F0012EB000400024Q003800056Q000600040002000200061E0104008700013Q000437012Q008700010012EB0004001E4Q00230104000100020006340004008700010003000437012Q008700010012EB000400203Q0012EB0005000E4Q000600040002000200061E0104008700013Q000437012Q008700010012EB000400213Q0012EB0005000E4Q00310004000200010012EB000400223Q00061E0104007C00013Q000437012Q007C00010012EB000400173Q001243000500233Q001243000600244Q0040010400060001000437012Q007F00010012EB0004001B3Q001243000500234Q00310004000200010012EB000400253Q0012A00005001C6Q00040002000100122Q0004000A3Q00202Q00040004000B00122Q000500266Q00040002000100044Q006300010012EB000400024Q003800056Q00060004000200020006F20004008D00010001000437012Q008D00012Q00583Q00013Q001243000400083Q00127B010400143Q00122Q000400276Q0004000100014Q000400043Q00122Q0004001C3Q00122Q000400103Q00262Q0004009A00010028000437012Q009A00010012EB000400293Q00203600040004001D00129F000400293Q000437012Q009D00010012EB0004002A3Q00203600040004001D00129F0004002A3Q0012EB0004002B3Q0012970005000E6Q00068Q00040006000100122Q000400026Q00058Q00040002000200062Q000400A700010001000437012Q00A700012Q00583Q00013Q0012EB0004002C3Q0012CF0005000E6Q00068Q0004000600014Q000400043Q00122Q0004000E3Q00122Q0004002D3Q00122Q000400106Q000400043Q00122Q0004001C3Q00122Q0004002E6Q00040001000100122Q0004002F6Q00058Q00040002000200062Q000400B900010001000437012Q00B900012Q00583Q00014Q00583Q00017Q00143Q0003073Q00656E61626C6564030B3Q004661726D456E61626C6564030B3Q006661726D5365636F6E6473030E3Q006765744661726D5365636F6E647303053Q00706861736503093Q006661726D506861736503053Q0074722Q6573030F3Q0063616368656454722Q65436F756E7403063Q0073746F6E657303103Q0063616368656453746F6E65436F756E7403053Q0064726F7073030F3Q0063616368656444726F70436F756E7403093Q0074722Q6544726F707303103Q0073652Q73696F6E54722Q6544726F7073030A3Q0073746F6E6544726F707303113Q0073652Q73696F6E53746F6E6544726F7073030A3Q0074722Q65734D696E656403113Q0073652Q73696F6E54722Q65734D696E6564030B3Q0073746F6E65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E656400184Q00ED5Q000A00122Q000100023Q00104Q0001000100122Q000100046Q00010001000200104Q0003000100122Q000100063Q00104Q0005000100122Q000100083Q00104Q0007000100122Q0001000A3Q00104Q0009000100122Q0001000C3Q00104Q000B000100122Q0001000E3Q00104Q000D000100122Q000100103Q00104Q000F000100122Q000100123Q00104Q0011000100122Q000100143Q00104Q001300016Q00028Q00017Q000A3Q00030E3Q006661726D436865636B506175736503103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q00426C6F636B5569447572696E674661726D030B3Q004661726D456E61626C656403043Q0067656E7603153Q004D617869487562496E76556E626C6F636B656455692Q01030C3Q0073746F70536166654D6F646500134Q00B23Q00013Q00124Q00013Q00124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00053Q00064Q001200013Q000437012Q001200010012EB3Q00063Q00061E012Q001200013Q000437012Q001200010012EB3Q00073Q003019012Q000800090012EB3Q000A5Q00012Q000100012Q00583Q00017Q00073Q00030E3Q006661726D436865636B506175736503043Q0067656E7603153Q004D617869487562496E76556E626C6F636B65645569030B3Q004661726D456E61626C656403113Q00426C6F636B5569447572696E674661726D00030D3Q007374617274536166654D6F646500114Q00B17Q00124Q00013Q00124Q00023Q00206Q000300064Q001000013Q000437012Q001000010012EB3Q00043Q00061E012Q001000013Q000437012Q001000010012EB3Q00053Q00061E012Q001000013Q000437012Q001000010012EB3Q00023Q003019012Q000300060012EB3Q00075Q00012Q000100012Q00583Q00017Q000C3Q0003043Q007479706503063Q00737472696E67034Q002Q033Q00737562026Q00F03F03013Q003C026Q00794003053Q006C6F77657203043Q0066696E6403093Q003C21646F63747970650003053Q003C68746D6C01273Q0012EB000100014Q008401026Q00060001000200020026392Q01000D00010002000437012Q000D00010026BF3Q000D00010003000437012Q000D00010020BC00013Q0004001243000300053Q001243000400054Q003F2Q01000400020026BF0001000F00010006000437012Q000F00012Q00D300016Q00FF000100023Q0020BC00013Q000400121C010300053Q00122Q000400076Q00010004000200202Q0001000100084Q00010002000200202Q00020001000900122Q0004000A3Q00122Q000500056Q000600016Q00020006000200262Q000200240001000B000437012Q002400010020BC0002000100090012390004000C3Q00122Q000500056Q000600016Q00020006000200262Q000200240001000B000437012Q002400012Q001B00026Q00D3000200014Q00FF000200024Q00583Q00017Q00063Q0003043Q0067616D6503073Q00482Q747047657403123Q006D6178692D6875622D75692E6C75613F763D03083Q00746F737472696E6703023Q006F7303043Q0074696D65000E3Q00123F3Q00013Q00206Q00024Q00025Q00122Q000300033Q00122Q000400043Q00122Q000500053Q00202Q0005000500064Q000500016Q00043Q00024Q0002000200044Q000300018Q00039Q008Q00017Q00393Q0003083Q0074656C656772616D030D3Q0054454C454752414D5F4C494E4B030A3Q007363726970744C696E65031E3Q00D090D0B2D182D0BE2DD184D0B0D180D0BC20D181D0BAD180D0B8D0BFD182030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C6973745772617003083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D32026Q00F03F028Q00026Q00504003103Q004261636B67726F756E64436F6C6F723303063Q00434F4C4F525303053Q0070616E656C030F3Q00426F7264657253697A65506978656C03043Q00466F6E7403043Q00456E756D03063Q00476F7468616D03083Q005465787453697A65026Q002840030A3Q0054657874436F6C6F723303043Q0074657874030B3Q00546578745772612Q7065642Q0103043Q0054657874030C3Q005343524950545F5449544C4503013Q000A032E3Q000AD0A1D0BFD0B0D181D0B8D0B1D0BE20D187D182D0BE20D0BFD0BED0BBD18CD0B7D183D0B5D188D18CD181D18F21030B3Q004C61796F75744F7264657203063Q00506172656E7403093Q00612Q64436F726E6572026Q00204003093Q00554950612Q64696E67030A3Q0050612Q64696E67546F7003043Q005544696D026Q002440030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E675269676874030A3Q005465787442752Q746F6E026Q00444003063Q00612Q63656E74030A3Q00476F7468616D426F6C64026Q002A4003023Q00626703133Q0054656C656772616D20D0BAD0B0D0BDD0B0D0BB030F3Q004175746F42752Q746F6E436F6C6F720100027Q0040026Q002Q4003163Q004261636B67726F756E645472616E73706172656E637903053Q006D75746564026Q00084003113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E656374038E3Q0006F20002000400010001000437012Q000400012Q00AF00036Q0084010200033Q0020080103000200010006F20003000800010001000437012Q000800010012EB000300023Q0020080104000200030006F20004000C00010001000437012Q000C0001001243000400043Q0020080105000100052Q000700068Q00050002000200202Q0006000100064Q000700056Q00060002000200122Q000700073Q00202Q00070007000800122Q000800096Q00070002000200122Q0008000B3Q00202Q00080008000800122Q0009000C3Q00122Q000A000D3Q00122Q000B000D3Q00122Q000C000E6Q0008000C000200102Q0007000A000800202Q00080001001000202Q00080008001100102Q0007000F000800302Q00070012000D00122Q000800143Q00202Q00080008001300202Q00080008001500102Q00070013000800302Q00070016001700202Q00080001001000202Q00080008001900102Q00070018000800302Q0007001A001B00122Q0008001D3Q00122Q0009001E6Q000A00043Q00122Q000B001F6Q00080008000B00102Q0007001C000800302Q00070020000C00102Q00070021000600202Q0008000100224Q000900073Q00122Q000A00236Q0008000A000100122Q000800073Q00202Q00080008000800122Q000900246Q00080002000200122Q000900263Q00202Q00090009000800122Q000A000D3Q00122Q000B00276Q0009000B000200102Q00080025000900122Q000900263Q00202Q00090009000800122Q000A000D3Q00122Q000B00176Q0009000B000200102Q00080028000900122Q000900263Q00202Q00090009000800122Q000A000D3Q00122Q000B00176Q0009000B000200102Q00080029000900102Q00080021000700122Q000900073Q00202Q00090009000800122Q000A002A6Q00090002000200122Q000A000B3Q00202Q000A000A000800122Q000B000C3Q00122Q000C000D3Q00122Q000D000D3Q00122Q000E002B6Q000A000E000200102Q0009000A000A00202Q000A0001001000202Q000A000A002C00102Q0009000F000A00301901090012000D0012C8000A00143Q00202Q000A000A001300202Q000A000A002D00102Q00090013000A00302Q00090016002E00202Q000A0001001000202Q000A000A002F00102Q00090018000A00302Q0009001C003000302Q00090031003200302Q00090020003300102Q00090021000600202Q000A000100224Q000B00093Q00122Q000C00236Q000A000C000100122Q000A00073Q00202Q000A000A000800122Q000B00096Q000A0002000200122Q000B000B3Q00202Q000B000B000800122Q000C000C3Q00122Q000D000D3Q00122Q000E000D3Q00122Q000F00346Q000B000F000200102Q000A000A000B00302Q000A0035000C00122Q000B00143Q00202Q000B000B001300202Q000B000B001500102Q000A0013000B00302Q000A0016002700202Q000B0001001000202Q000B000B003600102Q000A0018000B00302Q000A001A001B00102Q000A001C000300302Q000A0020003700102Q000A0021000600202Q000B0009003800202Q000B000B0039000675010D3Q000100022Q0084012Q00034Q0084012Q00094Q0040010B000D00012Q00583Q00013Q00013Q00063Q0003053Q007063612Q6C03043Q005465787403173Q00D0A1D0BAD0BED0BFD0B8D180D0BED0B2D0B0D0BDD0BE2103043Q007461736B03053Q0064656C6179026Q00F83F000D3Q0012EB3Q00013Q0006752Q013Q000100012Q00388Q00A13Q000200016Q00013Q00304Q0002000300124Q00043Q00206Q000500122Q000100063Q00067501020001000100012Q00383Q00014Q0040012Q000200012Q00583Q00013Q00023Q00013Q00030C3Q00736574636C6970626F61726400043Q0012EB3Q00014Q003800016Q00313Q000200012Q00583Q00017Q00033Q0003063Q00506172656E7403043Q005465787403133Q0054656C656772616D20D0BAD0B0D0BDD0B0D0BB00074Q00387Q002008014Q000100061E012Q000600013Q000437012Q000600012Q00387Q003019012Q000200032Q00583Q00017Q0028012Q00030F3Q00687562422Q6F74737472612Q706564030A3Q006C6F6164436F6E66696703073Q007461624465667303043Q006E616D65030E3Q00D093D0BBD0B0D0B2D0BDD0B0D18F03053Q007469746C6503083Q007375627469746C6503463Q00D0A3D0BFD180D0B0D0B2D0BBD0B5D0BDD0B8D0B520D184D0B0D180D0BCD0BED0BC20D0B820D181D182D0B0D182D0B8D181D182D0B8D0BAD0B020D181D0B5D181D181D0B8D0B803123Q00D09DD0B0D181D182D180D0BED0B9D0BAD0B803413Q00D094D0BED0B1D18BD187D0B02C20D0B1D0B5D0B7D0BED0BFD0B0D181D0BDD0BED181D182D18C20D0B820D0B0D0B2D182D0BE2DD0BFD180D0BED0B4D0B0D0B6D0B003073Q00446973636F726403343Q00576562682Q6F6B2C20D182D0B0D0B9D0BCD0B8D0BDD0B3D0B820D0B820D182D0B5D181D18220D0BED182D187D191D182D0BED0B2030E3Q00D09AD180D0B5D0B4D0B8D182D18B03253Q00D09E20D181D0BAD180D0B8D0BFD182D0B520D0B820D0BAD0BED0BDD182D0B0D0BAD182D18B03023Q007569030C3Q004D61786948756255494C696203063Q0063726561746503063Q00706C6179657203093Q00706C6179657247756903043Q0067656E76030C3Q005343524950545F5449544C4503073Q006775694E616D6503083Q004755495F4E414D45030D3Q007361766564506F736974696F6E030A3Q0073617665645569506F73030F3Q0064656661756C74506F736974696F6E030E3Q0044454641554C545F55495F504F5303093Q007469746C6548696E74032E3Q00456E6420E2809420D184D0B0D180D0BC20C2B72052696768744374726C20E2809420D181D0BAD180D18BD182D18C03043Q0074616273030D3Q006B657953746174757354657874030E3Q006F6E53617665506F736974696F6E03123Q007363686564756C6553617665436F6E66696703093Q006F6E44657374726F79030A3Q0066752Q6C556E6C6F6164030D3Q006F6E43616D6572615374617274030F3Q00737461727443616D6572614C2Q6F7003063Q00434F4C4F5253030C3Q00636F6E74656E74506167657303093Q00612Q64436F726E657203093Q0073776974636854616203103Q006D616B6553656374696F6E5469746C65030A3Q006D616B65546F2Q676C65030A3Q006D616B65536C69646572030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C69737457726170030D3Q006D616B65466C6F7750616E656C030B3Q006D616B6553746174526F77030E3Q006D616B65466C6F77546F2Q676C6503093Q007363722Q656E47756903063Q007569522Q6F7403063Q007569426F6479030C3Q007363722Q656E477569526566030C3Q006D61696E4672616D6552656603133Q00666F726D617453652Q73696F6E54696D65556903103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503113Q0073652Q73696F6E537461744C6162656C73030C3Q007365744661726D537461746503083Q006D61696E50616765026Q00F03F03013Q004C03093Q0055495F4C41594F5554030D3Q00636F6E74726F6C7350616E656C03143Q00D0A3D0BFD180D0B0D0B2D0BBD0B5D0BDD0B8D0B503073Q0050414E454C5F57026Q006940028Q0003223Q00D0A1D182D0B0D180D18220D0BFD180D0B820D0B7D0B0D0B3D180D183D0B7D0BAD0B5030D3Q004175746F53746172744661726D02295C8FC2F528CC3F03113Q00D090D0B2D182D0BE20D184D0B0D180D0BC027Q0040026Q00E03F03293Q00D090D0B2D182D0BE20D0BFD180D0B820D181D0BCD0B5D0BDD0B520D181D0B5D180D0B2D0B5D180D0B0030E3Q0052656A6F696E4175746F4C6F6164026Q00084002F6285C8FC2F5E83F030C3Q0073652Q73696F6E50616E656C030C3Q00D0A1D0B5D181D181D0B8D18F03073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58030E3Q0053452Q53494F4E5F424F44595F5903053Q007068617365030C3Q00D0A1D182D0B0D182D183D18103053Q0074722Q6573031D3Q00D0A1D180D183D0B1D0B8D0BB20D0B4D0B5D180D0B5D0B2D18CD0B5D0B203063Q0073746F6E657303193Q00D0A1D180D183D0B1D0B8D0BB20D0BAD0B0D0BCD0BDD0B5D0B903043Q006C2Q6F7403163Q00D09BD183D18220D0BDD0B020D0B7D0B5D0BCD0BBD0B5026Q00104003043Q0074696D6503153Q00D092D180D0B5D0BCD18F20D184D0B0D180D0BCD0B0026Q00144003043Q006D6F6465030A3Q00D0A0D0B5D0B6D0B8D0BC026Q001840030C3Q00736C696465727350616E656C03113Q00D092D18BD181D0BED182D0B020D0A2D09F03063Q0046552Q4C5F57030E3Q00534C494445525F50414E454C5F4803063Q00524F57335F59030D3Q00534C494445525F424F44595F59030E3Q00D094D0B5D180D0B5D0B2D18CD18F026Q002840030E3Q0054656C65706F7274486569676874030D3Q00534C494445525F595F53544550030A3Q00D09AD0B0D0BCD0BDD0B803133Q0053746F6E6554656C65706F7274486569676874030B3Q007374617475734C6162656C03083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D3203073Q0056697369626C65010003063Q00506172656E7403093Q007365745363726F2Q6C03073Q0073657457726170030C3Q00D0B4D0BED0B1D18BD187D0B003073Q006D696E65426F7803053Q004672616D65030A3Q004D494E455F424F585F4803163Q004261636B67726F756E645472616E73706172656E6379030B3Q004C61796F75744F7264657203263Q00D09AD180D183D0B6D0B5D0BDD0B8D0B520D0B2D0BED0BAD180D183D0B320D186D0B5D0BBD0B8030C3Q004F72626974456E61626C6564030D3Q00544F2Q474C455F595F5354455003163Q00D090D182D0B0D0BAD0B020D0B220D186D0B5D0BBD18C030B3Q0041696D417454617267657403103Q00D09AD0BBD0B0D0B2D0B8D188D0B0204603073Q00557365464B6579030F3Q00D09AD0BBD0B8D0BA20D09BD09AD09C03083Q00557365436C69636B030A3Q00736C6964657273426F78030D3Q00534C49444552535F424F585F48031B3Q00D0A1D0BAD0BED180D0BED181D182D18C20D0BAD180D183D0B3D0B0026Q33D33F030A3Q004F7262697453702Q656403193Q00D094D0B8D0B0D0BCD0B5D182D18020D0BAD180D183D0B3D0B0026Q003E40030D3Q004F726269744469616D6574657203183Q00D0B1D0B5D0B7D0BED0BFD0B0D181D0BDD0BED181D182D18C03073Q0073616665426F78030A3Q00534146455F424F585F48031D3Q00D091D0BBD0BED0BA20554920D0BFD180D0B820D184D0B0D180D0BCD0B503113Q00426C6F636B5569447572696E674661726D03173Q00D091D0BBD0BED0BA20D182D180D0B5D0B9D0B4D0BED0B2030B3Q00426C6F636B54726164657303093Q00626C6F636B48696E74026Q00324003043Q00466F6E7403043Q00456E756D03063Q00476F7468616D03083Q005465787453697A65026Q002440030A3Q0054657874436F6C6F723303053Q006D75746564030E3Q005465787458416C69676E6D656E7403043Q004C65667403043Q0054657874033A3Q00D0A1D0BAD180D18BD0B2D0B0D0B5D18220D0B8D0B3D180D0BED0B2D18BD0B520D0BCD0B5D0BDD18E20D0BFD180D0B820D184D0B0D180D0BCD0B5030D3Q00D0B0D0BDD182D0B82DD182D0BF026Q001C4003073Q007A6F6E65426F78026Q004640026Q00204003163Q00D090D0BDD182D0B82DD0A2D09F20D0B7D0BED0BDD0B003133Q00426C6F636B65645A6F6E6573456E61626C6564030D3Q007A6F6E65536C69646572426F78026Q00224003153Q00D0A0D0B0D0B7D0BCD0B5D18020D0BAD183D0B1D0B0026Q003440026Q005E40030F3Q00426C6F636B65645A6F6E6553697A65030A3Q007A6F6E6542746E526F77026Q004240030C3Q007A6F6E65506C61636542746E030A3Q005465787442752Q746F6E03103Q004261636B67726F756E64436F6C6F723303053Q0070616E656C030F3Q00426F7264657253697A65506978656C030A3Q00476F7468616D426F6C64026Q00264003043Q007465787403243Q00D09FD0BED181D182D0B0D0B2D0B8D182D18C20D0BAD183D0B120D0B7D0B4D0B5D181D18C030F3Q004175746F42752Q746F6E436F6C6F7203083Q007A6F6E6548696E74026Q002Q40030B3Q00546578745772612Q7065642Q01035B3Q00D09AD180D0B0D181D0BDD18BD0B920D0BAD183D0B120E2809420D0B7D0B0D0BFD180D0B5D18220D0BDD0B020D0A2D09F20D0B820D184D0B0D180D0BC2028D0B4D0B5D180D0B5D0B2D18CD18F20D0B820D0BAD0B0D0BCD0BDD0B82903113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E656374030A3Q00D186D0B5D0BDD182D18003063Q00687562426F78026Q002A40031A3Q00D09FD0B0D183D0B7D0B020D18320D181D0BFD0B0D0B2D0BDD0B0030E3Q0048756257616974456E61626C656403073Q0068756248696E74026Q003C4003443Q00D092D18BD0BAD0BB20E2809420D0A2D09F20D0B220D186D0B5D0BDD182D18020D0B1D0B5D0B720D0BED0B6D0B8D0B4D0B0D0BDD0B8D18F2033E280933820D181D0B5D0BA026Q002C40030E3Q00D0BFD180D0BED0B4D0B0D0B6D0B0026Q002E4003073Q0073652Q6C426F78026Q005840026Q00304003173Q00D090D0B2D182D0BE20D0BFD180D0BED0B4D0B0D0B6D0B0030F3Q004175746F53652Q6C456E61626C656403193Q00D09FD180D0BED0B2D0B5D180D0BAD0B02028D181D0B5D0BA2903113Q0053652Q6C436865636B496E74657276616C030A3Q0073652Q6C42746E526F77026Q003140030D3Q006D616E75616C53652Q6C42746E03063Q00612Q63656E7403023Q006267031B3Q00D09FD180D0BED0B4D0B0D182D18C20D181D0B5D0B9D187D0B0D181030A3Q0073652Q6C537461747573034Q0003083Q0073652Q6C48696E74037F3Q00D090D0B2D182D0BE3A20D0BBD18ED0B1D0BED0B920D0BFD180D0B5D0B4D0BCD0B5D182203E20383Q392E20D09FD180D0B820D0A2D09F20D0B220D0B4D180D183D0B3D0BED0B920D0BFD0BBD0B5D0B9D18120D0BFD180D0BED0B3D180D0B5D181D18120D0B2206D6178692D6875622D73652Q6C2D73746174652E6A736F6E026Q003340030D3Q00646973636F72645363726F2Q6C030B3Q00646973636F726457726170030A3Q00776562682Q6F6B426F78025Q0080524003043Q0063617264030C3Q00776562682Q6F6B5469746C65026Q0034C003083Q00506F736974696F6E030B3Q00576562682Q6F6B2055524C030C3Q00776562682Q6F6B496E70757403073Q0054657874426F7803103Q00436C656172546578744F6E466F637573030F3Q00506C616365686F6C6465725465787403243Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F3Q2E03113Q00506C616365686F6C646572436F6C6F723303123Q0055736572446973636F7264576562682Q6F6B030D3Q00646973636F726453746174757303103Q0063616E557365436F6E66696746696C65032E3Q00D0A1D0BED185D180D0B0D0BDD18FD0B5D182D181D18F20D0B2206D6178692D6875622D636F6E6669672E6A736F6E03473Q00D0A4D0B0D0B9D0BBD18B20D0BDD0B5D0B4D0BED181D182D183D0BFD0BDD18B20E2809420776562682Q6F6B20D0B4D0BE20D0BFD0B5D180D0B5D0B7D0B0D0BFD183D181D0BAD0B0030B3Q00646973636F72644F707473025Q00406A4003113Q00646973636F72644F7074734C61796F7574030C3Q0055494C6973744C61796F757403073Q0050612Q64696E6703043Q005544696D03093Q00536F72744F72646572030A3Q00646973636F726450616403093Q00554950612Q64696E67030A3Q0050612Q64696E67546F70030D3Q0050612Q64696E67426F2Q746F6D030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E67526967687403173Q00D09ED182D187D191D182D18B20D0B220446973636F726403153Q00446973636F72645265706F727473456E61626C656403203Q00D09BD0BED0B320D0BFD180D0B820D0BED181D182D0B0D0BDD0BED0B2D0BAD0B503103Q00446973636F72644C6F674F6E53746F7003203Q00D09BD0BED0B320D0BFD0BED181D0BBD0B520D0BFD180D0BED0B4D0B0D0B6D0B803103Q00446973636F72644C6F674F6E53652Q6C030B3Q00696E74657276616C426F78026Q0020C0026Q004A4003193Q00D098D0BDD182D0B5D180D0B2D0B0D0BB2028D0BCD0B8D0BD2903143Q00446973636F72645265706F72744D696E75746573030B3Q00646973636F726442746E7303073Q007465737442746E02B81E85EB51B8DE3F03103Q00D0A2D0B5D181D18220776562682Q6F6B03073Q007361766542746E02A4703D0AD7A3E03F03123Q00D0A1D0BED185D180D0B0D0BDD0B8D182D18C030B3Q00646973636F726448696E74026Q00484003533Q00D0A1D18ED0B4D0B020D0B8D0B4D183D18220D0BBD0BED0B3D0B820D184D0B0D180D0BCD0B03A20D181D180D183D0B1D0B8D0BB2C20D0BBD183D1822C20D0B2D180D0B5D0BCD18F2C205265736F75726365732E03153Q00612Q706C79576562682Q6F6B46726F6D496E70757403093Q00466F6375734C6F737403163Q006275696C644D61786948756243726564697473546162030A3Q007363726970744C696E65031E3Q00D090D0B2D182D0BE2DD184D0B0D180D0BC20D181D0BAD180D0B8D0BFD182030C3Q006F6E496E707574426567616E03083Q0066696E616C697A6503043Q007461736B03053Q00737061776E03173Q00757064617465426C6F636B65645A6F6E6556697375616C03133Q0068617350656E64696E6753652Q6C5374617465031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F74737472617003053Q00646566657203063Q00747970656F6603153Q004D617869487562526567697374657252656A6F696E03083Q0066756E6374696F6E03053Q007063612Q6C00CA052Q0012EB3Q00013Q00061E012Q000400013Q000437012Q000400012Q00583Q00014Q00D33Q00013Q0012693Q00013Q00124Q00028Q000100016Q00046Q00013Q000300302Q00010004000500302Q00010006000500302Q0001000700084Q00023Q000300302Q00020004000900302Q00020006000900302Q00020007000A4Q00033Q000300302Q00030004000B00302Q00030006000B00302Q00030007000C4Q00043Q000300302Q00040004000D00302Q00040006000D00302Q00040007000E6Q0004000100129F3Q00033Q001280012Q00103Q00206Q00114Q00013Q000D00122Q000200123Q00102Q00010012000200122Q000200133Q00102Q00010013000200122Q000200143Q00102Q00010014000200122Q000200153Q00102Q00010006000200122Q000200173Q00102Q00010016000200122Q000200193Q00102Q00010018000200122Q0002001B3Q00102Q0001001A000200302Q0001001C001D00122Q000200033Q00102Q0001001E000200027200025Q0010F90001001F000200122Q000200213Q00102Q00010020000200122Q000200233Q00102Q00010022000200122Q000200253Q00102Q0001002400026Q0002000200124Q000F3Q00124Q000F3Q00206Q002600124Q00263Q00124Q000F3Q00206Q002700124Q00273Q00124Q000F3Q00206Q002800124Q00283Q00124Q000F3Q00206Q002900124Q00293Q00124Q000F3Q00206Q002A00124Q002A3Q00124Q000F3Q00206Q002B00124Q002B3Q00124Q000F3Q00206Q002C00124Q002C3Q00124Q000F3Q00206Q002D00124Q002D3Q00124Q000F3Q00206Q002E00124Q002E3Q00124Q000F3Q00206Q002F00124Q002F3Q00124Q000F3Q00206Q003000124Q00303Q00124Q000F3Q00206Q003100124Q00313Q00124Q000F3Q00206Q003200124Q00323Q00124Q000F3Q00206Q003300124Q00333Q00124Q000F3Q00206Q003400124Q00343Q00124Q00323Q00124Q00353Q00124Q000F3Q00206Q003300124Q00363Q0002723Q00013Q0012EF3Q00379Q003Q00124Q00389Q003Q00124Q00394Q00AF7Q00129F3Q003A3Q0002723Q00023Q00124A012Q003B3Q00124Q00273Q00206Q003D00124Q003C3Q00124Q003F3Q00124Q003E3Q00124Q002F3Q00122Q0001003C3Q00122Q000200413Q00122Q0003003E3Q00207E00030003004200122Q000400433Q00122Q000500443Q00122Q000600448Q0006000200129F3Q00403Q0012EB3Q00313Q0012EB000100403Q001243000200453Q0012EB000300463Q000272000400033Q0012BB0005003D3Q00122Q000600478Q0006000100124Q00313Q00122Q000100403Q00122Q000200486Q00035Q000272000400043Q001287000500493Q00122Q0006004A8Q0006000200124Q00393Q00124Q00313Q00122Q000100403Q00122Q0002004B3Q00122Q0003004C3Q000272000400053Q0012AD0005004D3Q00122Q0006004E8Q0006000100124Q002F3Q00122Q0001003C3Q00122Q000200503Q00122Q0003003E3Q00202Q00030003004200122Q0004003E3Q00202Q00040004005100122Q0005003E3Q00202Q00050005005200122Q000600443Q00122Q0007003E3Q00202Q0007000700536Q0007000200124Q004F3Q00124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300553Q00122Q0004003D6Q00010004000200104Q0054000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300573Q00122Q000400496Q00010004000200104Q0056000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300593Q00122Q0004004D6Q00010004000200104Q0058000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q0003005B3Q00122Q0004005C6Q00010004000200104Q005A000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q0003005E3Q00122Q0004005F6Q00010004000200104Q005D000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300613Q00122Q000400626Q00010004000200104Q0060000100124Q002F3Q00122Q0001003C3Q00122Q000200643Q00122Q0003003E3Q00202Q00030003006500122Q0004003E3Q00202Q00040004006600122Q000500443Q00122Q0006003E3Q00202Q00060006006700122Q0007003E3Q00202Q0007000700686Q0007000200124Q00633Q00124Q002C3Q00122Q000100633Q00122Q000200443Q00122Q000300693Q00122Q000400443Q00122Q0005006A3Q00122Q0006006B3Q000272000700064Q00263Q0007000100124Q002C3Q00122Q000100633Q00122Q0002003E3Q00202Q00020002006C00122Q0003006D3Q00122Q000400443Q00122Q0005006A3Q00122Q0006006E3Q000272000700074Q007A3Q0007000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q006F3Q00124Q006F3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500446Q00010005000200104Q0073000100124Q006F3Q00304Q0075007600124Q006F3Q00122Q0001003C3Q00104Q0077000100124Q002D3Q00122Q000100273Q00202Q0001000100496Q0002000200124Q00783Q00124Q002E3Q00122Q000100788Q0002000200124Q00793Q00124Q002A3Q00122Q000100793Q00122Q0002007A3Q00122Q0003003D8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q007B3Q00124Q007B3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q00050005007D4Q00010005000200104Q0073000100124Q007B3Q00304Q007E003D00124Q007B3Q00304Q007F004900124Q007B3Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q0001007B3Q00122Q000200443Q00122Q000300803Q00122Q000400813Q000272000500084Q00653Q0005000100124Q002B3Q00122Q0001007B3Q00122Q0002003E3Q00202Q00020002008200122Q000300833Q00122Q000400843Q000272000500094Q00D83Q0005000100124Q002B3Q00122Q0001007B3Q00122Q0002003E3Q00202Q00020002008200202Q00020002004900122Q000300853Q00122Q000400863Q0002720005000A4Q00D83Q0005000100124Q002B3Q00122Q0001007B3Q00122Q0002003E3Q00202Q00020002008200202Q00020002004D00122Q000300873Q00122Q000400883Q0002720005000B4Q00013Q0005000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00893Q00124Q00893Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q00050005008A4Q00010005000200104Q0073000100124Q00893Q00304Q007E003D00124Q00893Q00304Q007F004D00124Q00893Q00122Q000100793Q00104Q0077000100124Q002C3Q00122Q000100893Q00122Q000200443Q00122Q0003008B3Q00122Q0004008C3Q00122Q0005004D3Q00122Q0006008D3Q0002720007000C4Q00263Q0007000100124Q002C3Q00122Q000100893Q00122Q0002003E3Q00202Q00020002006C00122Q0003008E3Q00122Q0004005C3Q00122Q0005008F3Q00122Q000600903Q0002720007000D4Q00623Q0007000100124Q002A3Q00122Q000100793Q00122Q000200913Q00122Q0003005C8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00923Q00124Q00923Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q0005000500934Q00010005000200104Q0073000100124Q00923Q00304Q007E003D00124Q00923Q00304Q007F005F00124Q00923Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q000100923Q00122Q000200443Q00122Q000300943Q00122Q000400953Q0002720005000E4Q00653Q0005000100124Q002B3Q00122Q000100923Q00122Q0002003E3Q00202Q00020002008200122Q000300963Q00122Q000400973Q0002720005000F4Q000E3Q0005000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00983Q00124Q00983Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500996Q00010005000200104Q0073000100124Q00983Q00304Q007E003D00124Q00983Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00983Q00304Q009D009E00124Q00983Q00122Q000100263Q00202Q0001000100A000104Q009F000100124Q00983Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00983Q00304Q00A300A400124Q00983Q00304Q007F006200124Q00983Q00122Q000100793Q00104Q0077000100124Q002A3Q00122Q000100793Q00122Q000200A53Q00122Q000300A68Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00A73Q00124Q00A73Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500A86Q00010005000200104Q0073000100124Q00A73Q00304Q007E003D00124Q00A73Q00304Q007F00A900124Q00A73Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q000100A73Q00122Q000200443Q00122Q000300AA3Q00122Q000400AB3Q000272000500104Q00013Q0005000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00AC3Q00124Q00AC3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q00050005006C4Q00010005000200104Q0073000100124Q00AC3Q00304Q007E003D00124Q00AC3Q00304Q007F00AD00124Q00AC3Q00122Q000100793Q00104Q0077000100124Q002C3Q00122Q000100AC3Q00122Q000200443Q00122Q000300AE3Q00122Q000400AF3Q00122Q000500B03Q00122Q000600B13Q000272000700114Q00193Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00B23Q00124Q00B23Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q00B23Q00304Q007E003D00124Q00B23Q00304Q007F009E00124Q00B23Q00122Q000100793Q00104Q0077000100124Q00703Q00206Q007100122Q000100B58Q0002000200124Q00B43Q00124Q00B43Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q0004003D3Q00122Q000500446Q00010005000200104Q0073000100124Q00B43Q00122Q000100263Q00202Q0001000100B700104Q00B6000100124Q00B43Q00304Q00B8004400124Q00B43Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q00B43Q00304Q009D00BA00124Q00B43Q00122Q000100263Q00202Q0001000100BB00104Q009F000100124Q00B43Q00304Q00A300BC00124Q00B43Q00304Q00BD007600124Q00B43Q00122Q000100B23Q00104Q0077000100124Q00283Q00122Q000100B43Q00122Q000200A98Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00BE3Q00124Q00BE3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500BF6Q00010005000200104Q0073000100124Q00BE3Q00304Q007E003D0012D03Q00BE3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00BE3Q00304Q009D009E00124Q00BE3Q00122Q000100263Q00202Q0001000100A000101C3Q009F00010012333Q00BE3Q00304Q00C000C100124Q00BE3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00BE3Q00304Q00A300C200124Q00BE3Q003019012Q007F00BA00125A012Q00BE3Q00122Q000100793Q00104Q0077000100124Q00B43Q00206Q00C300206Q00C4000272000200124Q000E012Q0002000100124Q002A3Q00122Q000100793Q00122Q000200C53Q00122Q0003006A8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00C63Q00124Q00C63Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500A86Q00010005000200104Q0073000100124Q00C63Q00304Q007E003D00124Q00C63Q00304Q007F00C700124Q00C63Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q000100C63Q00122Q000200443Q00122Q000300C83Q00122Q000400C93Q000272000500134Q006D012Q0005000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00CA3Q00124Q00CA3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500CB6Q00010005000200104Q0073000100124Q00CA3Q00304Q007E003D00124Q00CA3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00CA3Q00304Q009D009E00124Q00CA3Q00122Q000100263Q00202Q0001000100A000104Q009F000100124Q00CA3Q00304Q00C000C100124Q00CA3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00CA3Q00304Q00A300CC00124Q00CA3Q00304Q007F00CD00124Q00CA3Q00122Q000100793Q00104Q0077000100124Q002A3Q00122Q000100793Q00122Q000200CE3Q00122Q000300CF8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00D03Q00124Q00D03Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500D16Q00010005000200104Q0073000100124Q00D03Q00304Q007E003D00124Q00D03Q00304Q007F00D200124Q00D03Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q000100D03Q00122Q000200443Q00122Q000300D33Q00122Q000400D43Q000272000500144Q00263Q0005000100124Q002C3Q00122Q000100D03Q00122Q0002003E3Q00202Q00020002008200122Q000300D53Q00122Q000400AF3Q00122Q000500B03Q00122Q000600D63Q000272000700154Q00193Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00D73Q00124Q00D73Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q00D73Q00304Q007E003D00124Q00D73Q00304Q007F00D800124Q00D73Q00122Q000100793Q00104Q0077000100124Q00703Q00206Q007100122Q000100B58Q0002000200124Q00D93Q00124Q00D93Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q0004003D3Q00122Q000500446Q00010005000200104Q0073000100124Q00D93Q00122Q000100263Q00202Q0001000100DA00104Q00B6000100124Q00D93Q00304Q00B8004400124Q00D93Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q00D93Q00304Q009D00BA00124Q00D93Q00122Q000100263Q00202Q0001000100DB00104Q009F000100124Q00D93Q00304Q00A300DC00124Q00D93Q00304Q00BD007600124Q00D93Q00122Q000100D73Q00104Q0077000100124Q00283Q00122Q000100D93Q00122Q000200A98Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00DD3Q00124Q00DD3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500D26Q00010005000200104Q0073000100124Q00DD3Q00304Q007E003D0012EB3Q00DD3Q0012770001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00DD3Q00304Q009D009E00124Q00DD3Q00122Q000100263Q00202Q0001000100A000104Q009F000100124Q00DD3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00DD3Q00304Q00A300DE00124Q00DD3Q00304Q007F009900124Q00DD3Q00122Q000100793Q00104Q0077000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00DF3Q00124Q00DF3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q00DF3Q00304Q007E003D00124Q00DF3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00DF3Q00304Q009D009E00124Q00DF3Q00122Q000100263Q00202Q0001000100A000104Q009F000100124Q00DF3Q00304Q00C000C100124Q00DF3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00DF3Q00304Q00A300E000124Q00DF3Q00304Q007F00E100124Q00DF3Q00122Q000100793Q00104Q0077000100124Q00D93Q00206Q00C300206Q00C4000272000200164Q005D3Q0002000100124Q002D3Q00122Q000100273Q00202Q00010001004D6Q0002000200124Q00E23Q00124Q002E3Q00122Q000100E28Q0002000200124Q00E33Q0012EB3Q00703Q0020755Q007100122Q0001007C8Q0002000200124Q00E43Q00124Q00E43Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q001243000500E54Q00E200010005000200104Q0073000100124Q00E43Q00122Q000100263Q00202Q0001000100E600104Q00B6000100124Q00E43Q00304Q00B8004400124Q00E43Q00304Q007F003D0012EB3Q00E43Q001215000100E33Q00104Q0077000100124Q00283Q00122Q000100E43Q00122Q0002009E8Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200129F3Q00E73Q001281012Q00E73Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300E83Q00122Q000400443Q00122Q000500996Q00010005000200104Q0073000100124Q00E73Q0012502Q0100743Q00202Q00010001007100122Q000200443Q00122Q0003009E3Q00122Q000400443Q00122Q000500A96Q00010005000200104Q00E9000100124Q00E73Q00304Q007E003D0012D03Q00E73Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q00E73Q00304Q009D00BA00124Q00E73Q00122Q000100263Q00202Q0001000100BB00101C3Q009F00010012EB3Q00E73Q0012EB0001009B3Q0020960001000100A100202Q0001000100A200104Q00A1000100124Q00E73Q00304Q00A300EA00124Q00E73Q00122Q000100E43Q00104Q0077000100124Q00703Q00206Q0071001243000100EC4Q0068012Q0002000200124Q00EB3Q00124Q00EB3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300E83Q00122Q000400443Q00122Q0005008F6Q00010005000200101C3Q00730001001281012Q00EB3Q00122Q000100743Q00202Q00010001007100122Q000200443Q00122Q0003009E3Q00122Q000400443Q00122Q000500BF6Q00010005000200104Q00E9000100124Q00EB3Q0012EB000100263Q0020B40001000100B700104Q00B6000100124Q00EB3Q00304Q00B8004400124Q00EB3Q00304Q00ED007600124Q00EB3Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00101C3Q009A000100125B012Q00EB3Q00304Q009D009E00124Q00EB3Q00122Q000100263Q00202Q0001000100BB00104Q009F000100124Q00EB3Q00304Q00EE00EF00124Q00EB3Q00122Q000100263Q0020082Q01000100A000109D3Q00F0000100124Q00EB3Q00122Q000100F13Q00104Q00A3000100124Q00EB3Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00EB3Q001215000100E43Q00104Q0077000100124Q00283Q00122Q000100EB3Q00122Q000200A98Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200129F3Q00F23Q001281012Q00F23Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500D26Q00010005000200104Q0073000100124Q00F23Q003019012Q007E003D0012D03Q00F23Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q00F23Q00304Q009D009E00124Q00F23Q00122Q000100263Q00202Q0001000100A000101C3Q009F00010012EB3Q00F23Q0012532Q01009B3Q00202Q0001000100A100202Q0001000100A200104Q00A1000100124Q00F23Q00122Q000100F36Q00010001000200062Q0001003904013Q000437012Q00390401001243000100F43Q0006F20001003A04010001000437012Q003A0401001243000100F53Q00101C3Q00A300010012833Q00F23Q00304Q007F004900124Q00F23Q00122Q000100E33Q00104Q0077000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00F63Q001281012Q00F63Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500F76Q00010005000200104Q0073000100124Q00F63Q0012EB000100263Q0020082Q01000100E60010C13Q00B6000100124Q00F63Q00304Q00B8004400124Q00F63Q00304Q007F004D00124Q00F63Q00122Q000100E33Q00104Q0077000100124Q00283Q00122Q000100F63Q0012430002009E4Q005A3Q0002000100124Q00703Q00206Q007100122Q000100F98Q0002000200124Q00F83Q00124Q00F83Q00122Q000100FB3Q00202Q00010001007100122Q000200443Q0012430003005C4Q009B00010003000200104Q00FA000100124Q00F83Q00122Q0001009B3Q00202Q0001000100FC00202Q00010001007F00104Q00FC000100124Q00F83Q00122Q000100F63Q00104Q007700010012EB3Q00703Q00202D5Q007100122Q000100FE8Q0002000200124Q00FD3Q00124Q00FD3Q00122Q000100FB3Q00202Q00010001007100122Q000200443Q00122Q000300A96Q00010003000200101C3Q00FF0001001204012Q00FD3Q00122Q000100FB3Q00202Q00010001007100122Q000200443Q00122Q000300A96Q00010003000200105Q002Q0100124Q00FD3Q00122Q0001002Q012Q00122Q000200FB3Q002008010200020071001243000300443Q0012430004005C4Q003F0102000400022Q0045012Q000100020012AA3Q00FD3Q00122Q00010002012Q00122Q000200FB3Q00202Q00020002007100122Q000300443Q00122Q0004005C6Q0002000400026Q0001000200124Q00FD3Q00122Q000100F63Q00104Q0077000100124Q00313Q00122Q000100F63Q00122Q00020003012Q00122Q00030004012Q000272000400173Q0012730105003D8Q0005000100124Q00313Q00122Q000100F63Q00122Q00020005012Q00122Q00030006012Q000272000400183Q001273010500498Q0005000100124Q00313Q00122Q000100F63Q00122Q00020007012Q00122Q00030008012Q000272000400193Q0012550105004D8Q0005000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q0009012Q00124Q0009012Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q0003000A012Q00122Q000400443Q00122Q0005000B015Q00010005000200104Q0073000100124Q0009012Q00122Q0001003D3Q00104Q007E000100124Q0009012Q00122Q0001005C3Q00104Q007F000100124Q0009012Q00122Q000100F63Q00104Q0077000100124Q002C3Q00122Q00010009012Q00122Q000200443Q00122Q0003000C012Q00122Q0004003D3Q00122Q000500B03Q00122Q0006000D012Q0002720007001A4Q0061012Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q000E012Q00124Q000E012Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500B36Q00010005000200104Q0073000100124Q000E012Q00122Q0001003D3Q00104Q007E000100124Q000E012Q00122Q0001005F3Q00104Q007F000100124Q000E012Q00122Q000100E33Q00104Q0077000100124Q00703Q00206Q007100122Q000100B58Q0002000200124Q000F012Q00124Q000F012Q00122Q000100743Q00202Q00010001007100122Q00020010012Q00122Q000300443Q00122Q0004003D3Q00122Q000500446Q00010005000200104Q0073000100124Q000F012Q00122Q000100263Q00202Q0001000100DA00104Q00B6000100124Q000F012Q00122Q000100443Q00104Q00B8000100124Q000F012Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q000F012Q00122Q000100BA3Q00104Q009D000100124Q000F012Q00122Q000100263Q00202Q0001000100DB00104Q009F000100124Q000F012Q00122Q00010011012Q00104Q00A3000100124Q000F015Q00015Q00104Q00BD000100124Q000F012Q00122Q0001000E012Q00104Q0077000100124Q00283Q00122Q0001000F012Q00122Q000200A98Q0002000100124Q00703Q00206Q007100122Q000100B58Q0002000200124Q0012012Q00124Q0012012Q00122Q000100743Q00202Q00010001007100122Q00020010012Q00122Q000300443Q0012430004003D3Q00123B000500446Q00010005000200104Q0073000100124Q0012012Q00122Q000100743Q00202Q00010001007100122Q00020013012Q00122Q000300443Q00122Q000400443Q00122Q000500446Q00010005000200104Q00E9000100124Q0012012Q00122Q000100263Q00202Q0001000100B700104Q00B6000100124Q0012012Q00122Q000100443Q00104Q00B8000100124Q0012012Q00122Q0001009B3Q00202Q00010001009A00202Q0001000100B900104Q009A000100124Q0012012Q00122Q000100BA3Q00104Q009D000100124Q0012012Q00122Q000100263Q00202Q0001000100BB00104Q009F000100124Q0012012Q00122Q00010014012Q00104Q00A3000100124Q0012015Q00015Q00104Q00BD000100124Q0012012Q00122Q0001000E012Q00104Q0077000100124Q00283Q00122Q00010012012Q00122Q000200A98Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q0015012Q00124Q0015012Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q00050016015Q00010005000200104Q0073000100124Q0015012Q00122Q0001003D3Q00104Q007E000100124Q0015012Q00122Q0001009B3Q00202Q00010001009A00202Q00010001009C00104Q009A000100124Q0015012Q00122Q0001009E3Q00104Q009D000100124Q0015012Q00122Q000100263Q00202Q0001000100A000104Q009F000100124Q0015015Q000100013Q00104Q00C0000100124Q0015012Q00122Q0001009B3Q00202Q0001000100A100202Q0001000100A20010323Q00A1000100124Q0015012Q00122Q00010017012Q00104Q00A3000100124Q0015012Q00122Q000100623Q00104Q007F000100124Q0015012Q00122Q000100E33Q00104Q007700010002723Q001B3Q00128D3Q0018012Q00124Q00EB3Q00122Q00010019019Q000100206Q00C40002720002001C4Q0040012Q000200010012EB3Q0012012Q002008014Q00C30020BC5Q00C40002720002001D4Q0040012Q000200010012EB3Q000F012Q002008014Q00C30020BC5Q00C40002720002001E4Q006F012Q0002000100124Q001A012Q00122Q000100273Q00122Q0002005C6Q0001000100024Q00023Q000400122Q000300263Q00102Q00020026000300122Q0003002D3Q00102Q0002002D000300122Q0003002E3Q00102Q0002002E000300122Q000300283Q00102Q0002002800034Q00033Q000100122Q0004001B012Q00122Q0005001C015Q0003000400056Q0003000100124Q000F3Q00122Q0001001D019Q00010002720001001F4Q000B3Q0002000100124Q000F3Q00122Q0001001E019Q00016Q0001000100124Q001F012Q00122Q00010020019Q0001000272000100204Q004D3Q0002000100124Q0021017Q0001000100124Q0022017Q0001000200064Q00B105013Q000437012Q00B105010012EB3Q0023014Q00012Q00010001000437012Q00B905010012EB3Q00463Q00061E012Q00B905013Q000437012Q00B905010012EB3Q001F012Q00124300010024013Q00AC5Q0001000272000100214Q00313Q000200010012EB3Q004C3Q00061E012Q00C905013Q000437012Q00C905010012EB3Q0025012Q0012302Q0100143Q00122Q00020026015Q0001000100026Q0002000200122Q00010027012Q00064Q00C905010001000437012Q00C905010012EB3Q0028012Q0012EB000100143Q00124300020026013Q00AC0001000100022Q00313Q000200012Q00583Q00013Q00223Q00053Q0003043Q0067656E76030E3Q004D6178694875624B65794761746503063Q00747970656F6603103Q006765744B65795374617475735465787403083Q0066756E6374696F6E000F3Q0012EB3Q00013Q002008014Q000200061E012Q000C00013Q000437012Q000C00010012EB000100033Q00200801023Q00042Q00060001000200020026392Q01000C00010005000437012Q000C00010020082Q013Q00042Q00652Q0100014Q00102Q016Q00AE000100014Q00FF000100024Q00583Q00017Q00093Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D6174030B3Q002564D0BC2025303264D18103023Q00D18100153Q0012303Q00018Q0001000200122Q000100023Q00202Q00010001000300202Q00023Q00044Q00010002000200202Q00023Q0004000E2Q0005001000010001000437012Q001000010012EB000300063Q00208A00030003000700122Q000400086Q000500016Q000600026Q000300066Q00036Q008401035Q001243000400094Q00F80003000300042Q00FF000300024Q00583Q00017Q000D3Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D03113Q0073652Q73696F6E54722Q65734D696E6564028Q0003123Q0073652Q73696F6E53746F6E65734D696E6564030E3Q006765744661726D5365636F6E6473026Q00344003083Q0073746F704661726D03103Q00446973636F72644C6F674F6E53746F7003043Q007461736B03053Q00646566657201353Q00061E012Q001100013Q000437012Q001100010012EB000100013Q00061E2Q01000600013Q000437012Q000600012Q00583Q00014Q00D3000100013Q0012A8000100023Q00122Q000100036Q000200016Q000300016Q0001000300014Q00015Q00122Q000100023Q00122Q000100046Q00010001000100044Q003400010012EB000100013Q0006F20001001500010001000437012Q001500012Q00583Q00013Q0012EB000100053Q000E0A0006002000010001000437012Q002000010012EB000100073Q000E0A0006002000010001000437012Q002000010012EB000100084Q00232Q0100010002000E0A0009002000010001000437012Q002000012Q001B00016Q00D3000100014Q008B000200013Q00122Q000200023Q00122Q000200036Q00038Q000400016Q0002000400014Q00025Q00122Q000200023Q00122Q0002000A6Q00020001000100061E2Q01003400013Q000437012Q003400010012EB0002000B3Q00061E0102003400013Q000437012Q003400010012EB0002000C3Q00200801020002000D00027200036Q00310002000200012Q00583Q00013Q00013Q00013Q0003053Q007063612Q6C00043Q0012EB3Q00013Q00027200016Q00313Q000200012Q00583Q00013Q00013Q00033Q0003153Q006C6F674661726D53652Q73696F6E446973636F7264031D3Q00D0A4D0B0D180D0BC20D0BED181D182D0B0D0BDD0BED0B2D0BBD0B5D0BD023Q008087E96C4100053Q00121D012Q00013Q00122Q000100023Q00122Q000200038Q000200016Q00017Q00023Q00030D3Q004175746F53746172744661726D03123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q0003103Q006661726D546F2Q676C6553696C656E74030C3Q007365744661726D537461746501083Q0012EB000100013Q00061E2Q01000400013Q000437012Q000400012Q00583Q00013Q0012EB000100024Q008401026Q00310001000200012Q00583Q00017Q00073Q00030E3Q0052656A6F696E4175746F4C6F616403123Q007363686564756C6553617665436F6E66696703063Q00747970656F6603043Q0067656E7603153Q004D617869487562526567697374657252656A6F696E03083Q0066756E6374696F6E03053Q007063612Q6C01103Q00129F3Q00013Q0012EB000100025Q002Q010001000100061E012Q000F00013Q000437012Q000F00010012EB000100033Q0012EB000200043Q0020080102000200052Q00060001000200020026392Q01000F00010006000437012Q000F00010012EB000100073Q0012EB000200043Q0020080102000200052Q00310001000200012Q00583Q00017Q00023Q00030E3Q0054656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q0003133Q0053746F6E6554656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q00030C3Q004F72626974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q00030B3Q0041696D417454617267657403123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q0003073Q00557365464B657903123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00033Q0003083Q00557365436C69636B03103Q0072656C656173654D6F757365486F6C6403123Q007363686564756C6553617665436F6E66696701083Q00129F3Q00013Q00061E012Q000500013Q000437012Q000500010012EB000100025Q002Q01000100010012EB000100035Q002Q01000100012Q00583Q00017Q00023Q00030A3Q004F7262697453702Q656403123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q00030D3Q004F726269744469616D6574657203123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q0003113Q00426C6F636B5569447572696E674661726D03123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00053Q00030B3Q00426C6F636B547261646573030B3Q004661726D456E61626C6564030A3Q007363616E54726164657303093Q00706C6179657247756903123Q007363686564756C6553617665436F6E666967010A3Q00129F3Q00013Q0012EB000100023Q00061E2Q01000700013Q000437012Q000700010012EB000100033Q0012EB000200044Q00310001000200010012EB000100055Q002Q01000100012Q00583Q00017Q00033Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E66696701063Q0012843Q00013Q00122Q000100026Q00010001000100122Q000100036Q0001000100016Q00017Q00053Q00030F3Q00426C6F636B65645A6F6E6553697A6503043Q006D61746803053Q00666C2Q6F7203173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E666967010A3Q001288000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q00010001000100122Q000100056Q0001000100016Q00017Q00083Q0003163Q00736574426C6F636B65645A6F6E654174506C61796572030C3Q007A6F6E65506C61636542746E03043Q0054657874031B3Q00D09AD183D0B120D183D181D182D0B0D0BDD0BED0B2D0BBD0B5D0BD03043Q007461736B03053Q0064656C6179026Q33F33F03193Q00D09DD0B5D18220D0BFD0B5D180D181D0BED0BDD0B0D0B6D0B0000F3Q0012EB3Q00014Q0023012Q0001000200061E012Q000C00013Q000437012Q000C00010012EB3Q00023Q003019012Q000300040012EB3Q00053Q002008014Q0006001243000100073Q00027200026Q0040012Q00020001000437012Q000E00010012EB3Q00023Q003019012Q000300082Q00583Q00013Q00013Q00043Q00030C3Q007A6F6E65506C61636542746E03063Q00506172656E7403043Q005465787403243Q00D09FD0BED181D182D0B0D0B2D0B8D182D18C20D0BAD183D0B120D0B7D0B4D0B5D181D18C00073Q0012EB3Q00013Q002008014Q000200061E012Q000600013Q000437012Q000600010012EB3Q00013Q003019012Q000300042Q00583Q00017Q00023Q00030E3Q0048756257616974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q00030F3Q004175746F53652Q6C456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00043Q0003113Q0053652Q6C436865636B496E74657276616C03043Q006D61746803053Q00666C2Q6F7203123Q007363686564756C6553617665436F6E66696701083Q00128E000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q0001000100016Q00017Q000C3Q00030E3Q0073652Q6C496E50726F6772652Q73030A3Q0073652Q6C53746174757303043Q0054657874031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B0030A3Q0054657874436F6C6F723303063Q00434F4C4F52532Q033Q00726564030D3Q006D616E75616C53652Q6C42746E03113Q00D09FD180D0BED0B4D0B0D0B6D0B03Q2E031B3Q00D0A2D09F20D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D1833Q2E03053Q006D75746564030D3Q0072756E4D616E75616C53652Q6C00163Q0012EB3Q00013Q00061E012Q000A00013Q000437012Q000A00010012EB3Q00023Q0030A63Q0003000400124Q00023Q00122Q000100063Q00202Q00010001000700104Q000500016Q00013Q0012EB3Q00083Q0030E43Q0003000900124Q00023Q00304Q0003000A00124Q00023Q00122Q000100063Q00202Q00010001000B00104Q0005000100124Q000C3Q00027200016Q00313Q000200012Q00583Q00013Q00013Q000A3Q00030D3Q006D616E75616C53652Q6C42746E03043Q0054657874031B3Q00D09FD180D0BED0B4D0B0D182D18C20D181D0B5D0B9D187D0B0D181030A3Q0073652Q6C537461747573030C3Q00D093D0BED182D0BED0B2D0BE030C3Q00D09ED188D0B8D0B1D0BAD0B0030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q0072656402173Q0012EB000200013Q0030190102000200030012EB000200043Q0006140103000B00010001000437012Q000B000100061E012Q000A00013Q000437012Q000A0001001243000300053Q0006F20003000B00010001000437012Q000B0001001243000300063Q00101C0002000200030012EB000200043Q00061E012Q001300013Q000437012Q001300010012EB000300083Q0020080103000300090006F20003001500010001000437012Q001500010012EB000300083Q00200801030003000A00101C0002000700032Q00583Q00017Q00053Q0003153Q00446973636F72645265706F727473456E61626C656403143Q004641524D5F5245504F52545F494E54455256414C03143Q00446973636F72645265706F72744D696E75746573026Q004E4003113Q0073617665446973636F7264436F6E66696701073Q00127C3Q00013Q00122Q000100033Q00202Q00010001000400122Q000100023Q00122Q000100056Q0001000100016Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53746F7003113Q0073617665446973636F7264436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53652Q6C03113Q0073617665446973636F7264436F6E66696701043Q00129F3Q00013Q0012EB000100025Q002Q01000100012Q00583Q00017Q00063Q0003143Q00446973636F72645265706F72744D696E7574657303043Q006D61746803053Q00666C2Q6F7203143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003113Q0073617665446973636F7264436F6E666967010B3Q0012832Q0100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100013Q00202Q00010001000500122Q000100043Q00122Q000100066Q0001000100016Q00017Q00083Q0003123Q0055736572446973636F7264576562682Q6F6B030C3Q00776562682Q6F6B496E70757403043Q005465787403043Q006773756203043Q005E25732B034Q0003043Q0025732B2403113Q0073617665446973636F7264436F6E666967000E3Q0012793Q00023Q00206Q000300206Q000400122Q000200053Q00122Q000300068Q0003000200206Q000400122Q000200073Q00122Q000300068Q0003000200124Q00013Q00124Q00088Q000100016Q00017Q00013Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757400033Q0012EB3Q00015Q00012Q000100012Q00583Q00017Q000A3Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E707574030D3Q00646973636F726453746174757303043Q005465787403123Q00D0A1D0BED185D180D0B0D0BDD0B5D0BDD0BE030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E7403043Q007461736B03053Q0064656C6179027Q0040000E3Q00123C012Q00018Q0001000100124Q00023Q00304Q0003000400124Q00023Q00122Q000100063Q00202Q00010001000700104Q0005000100124Q00083Q00206Q000900122Q0001000A3Q00027200026Q0040012Q000200012Q00583Q00013Q00013Q00093Q00030D3Q00646973636F726453746174757303063Q00506172656E7403043Q005465787403103Q0063616E557365436F6E66696746696C65032E3Q00D0A1D0BED185D180D0B0D0BDD18FD0B5D182D181D18F20D0B2206D6178692D6875622D636F6E6669672E6A736F6E03473Q00D0A4D0B0D0B9D0BBD18B20D0BDD0B5D0B4D0BED181D182D183D0BFD0BDD18B20E2809420776562682Q6F6B20D0B4D0BE20D0BFD0B5D180D0B5D0B7D0B0D0BFD183D181D0BAD0B0030A3Q0054657874436F6C6F723303063Q00434F4C4F525303053Q006D7574656400133Q0012EB3Q00013Q002008014Q000200061E012Q001200013Q000437012Q001200010012EB3Q00013Q0012EB000100044Q00232Q010001000200061E2Q01000C00013Q000437012Q000C0001001243000100053Q0006F20001000D00010001000437012Q000D0001001243000100063Q00101C3Q000300010012EB3Q00013Q0012EB000100083Q0020082Q010001000900101C3Q000700012Q00583Q00017Q00163Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757403103Q0073656E64446973636F7264456D62656403153Q006765744661726D446973636F7264576562682Q6F6B03113Q00D0A2D0B5D181D182204D41584920485542023Q00806D4C4A4103043Q006E616D6503103Q00D09FD180D0BED0B2D0B5D180D0BAD0B003053Q0076616C756503393Q00D095D181D0BBD0B820D0B2D0B8D0B4D0B8D188D18C20D18DD182D0BE20E2809420776562682Q6F6B20D180D0B0D0B1D0BED182D0B0D0B5D18203063Q00696E6C696E65010003103Q00D098D0BDD182D0B5D180D0B2D0B0D0BB03083Q00746F737472696E6703143Q00446973636F72645265706F72744D696E7574657303073Q0020D0BCD0B8D0BD2Q01030D3Q00646973636F726453746174757303043Q0054657874030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q0072656400243Q0012213Q00018Q0001000100124Q00023Q00122Q000100036Q00010001000200122Q000200043Q00122Q000300056Q000400026Q00053Q000300302Q00050006000700302Q00050008000900302Q0005000A000B4Q00063Q000300302Q00060006000C00122Q0007000D3Q00122Q0008000E6Q00070002000200122Q0008000F6Q00070007000800102Q00060008000700302Q0006000A00104Q0004000200012Q001A012Q000400010012EB000200113Q00101C0002001200010012EB000200113Q00061E012Q002000013Q000437012Q002000010012EB000300143Q0020080103000300150006F20003002200010001000437012Q002200010012EB000300143Q00200801030003001600101C0002001300032Q00583Q00017Q00093Q0003073Q004B6579436F646503063Q00484F544B455903043Q007469636B03043Q0067656E7603133Q004D6178694875624C617374486F746B65794174028Q0002CD5QCCDC3F030C3Q007365744661726D5374617465030B3Q004661726D456E61626C656401173Q0020082Q013Q00010012EB000200023Q00062A0001000500010002000437012Q000500012Q00583Q00013Q0012EB000100034Q00232Q01000100020012EB000200043Q0020080102000200050006F20002000C00010001000437012Q000C0001001243000200064Q00490002000100020026230002001000010007000437012Q001000012Q00583Q00013Q0012EB000200043Q00103801020005000100122Q000200083Q00122Q000300096Q000300036Q0002000200016Q00017Q00263Q0003093Q007363722Q656E47756903063Q00506172656E74030A3Q006163746976654E6F646503093Q006661726D506861736503043Q007761697403073Q00636F2Q6C656374030F3Q0063616368656444726F70436F756E74030D3Q0066696E6444726F70734E656172028Q00030A3Q0050484153455F54455854030B3Q006175746F46416374697665030D3Q0020C2B720D0B0D0B2D182D0BE46034Q00030F3Q006765744661726D4D6F64655465787403113Q0073652Q73696F6E537461744C6162656C7303053Q00706861736503043Q005465787403053Q0074722Q657303083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q0073746F6E657303123Q0073652Q73696F6E53746F6E65734D696E656403043Q006C2Q6F7403043Q0074696D6503133Q00666F726D617453652Q73696F6E54696D65556903043Q006D6F6465030B3Q007374617475734C6162656C03073Q0056697369626C65030F3Q004175746F53652Q6C456E61626C656403143Q0067657453652Q6C5472692Q676572416D6F756E7403063Q00737472696E6703063Q00666F726D617403083Q00207C2025733A256403233Q002573207C20D0B43A256420D0BA3A2564207C202573207C20D0BBD183D1823A25642573030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403043Q007461736B029A5Q99D93F00823Q0012EB3Q00013Q002008014Q000200061E012Q008100013Q000437012Q008100010012EB3Q00033Q00061E012Q001300013Q000437012Q001300010012EB3Q00043Q0026BF3Q000D00010005000437012Q000D00010012EB3Q00043Q002639012Q001300010006000437012Q001300010012EB3Q00083Q00124E000100038Q000200029Q0000124Q00073Q00044Q001500010012433Q00093Q00129F3Q00073Q0012EB3Q000A3Q0012EB000100044Q00AC5Q00010006F23Q001B00010001000437012Q001B00010012EB3Q00043Q0012EB0001000B3Q00061E2Q01002100013Q000437012Q002100010012430001000C3Q0006F20001002200010001000437012Q002200010012430001000D3Q0012EB0002000E4Q00230102000100020012EB0003000F3Q00200801030003001000061E0103002E00013Q000437012Q002E00010012EB0003000F3Q00201B0103000300104Q00048Q000500016Q00040004000500102Q0003001100040012EB0003000F3Q00200801030003001200061E0103003800013Q000437012Q003800010012EB0003000F3Q0020D600030003001200122Q000400133Q00122Q000500146Q00040002000200102Q0003001100040012EB0003000F3Q00200801030003001500061E0103004200013Q000437012Q004200010012EB0003000F3Q0020D600030003001500122Q000400133Q00122Q000500166Q00040002000200102Q0003001100040012EB0003000F3Q00200801030003001700061E0103004C00013Q000437012Q004C00010012EB0003000F3Q0020D600030003001700122Q000400133Q00122Q000500076Q00040002000200102Q0003001100040012EB0003000F3Q00200801030003001800061E0103005500013Q000437012Q005500010012EB0003000F3Q0020080103000300180012EB000400194Q002301040001000200101C0003001100040012EB0003000F3Q00200801030003001A00061E0103005C00013Q000437012Q005C00010012EB0003000F3Q00200801030003001A00101C0003001100020012EB0003001B3Q00061E0103007C00013Q000437012Q007C00010012EB0003001B3Q00200801030003001C00061E0103007C00013Q000437012Q007C00010012430003000D3Q0012EB0004001D3Q00061E0104007000013Q000437012Q007000010012EB0004001E4Q001800040001000500122Q0006001F3Q00202Q00060006002000122Q000700216Q000800056Q000900046Q0006000900024Q000300063Q0012EB0004001B3Q0012660105001F3Q00202Q00050005002000122Q000600226Q000700023Q00122Q000800233Q00122Q000900246Q000A5Q00122Q000B00076Q000C00036Q0005000C000200101C0004001100050012EB000300253Q002008010300030005001243000400264Q0031000300020001000437014Q00012Q00583Q00017Q00033Q0003103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C65030C3Q007365744661726D5374617465000C4Q00FE3Q00013Q00124Q00013Q00124Q00026Q000100016Q000200018Q000200019Q0000124Q00013Q00124Q00036Q000100018Q000200016Q00017Q00093Q00030C3Q00656E73757265506C6179657203043Q007761726E03393Q005B4D415849204855425D20D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD0BED0BBD183D187D0B8D182D18C20506C6179657247756903053Q007072696E74031D3Q005B4D415849204855425D20D0B7D0B0D0BFD183D181D0BA2055493Q2E03053Q007063612Q6C03103Q00622Q6F7473747261704D617869487562030F3Q00687562422Q6F74737472612Q70656403273Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0B7D0B0D0BFD183D181D0BAD0B03A00173Q0012EB3Q00014Q0023012Q000100020006F23Q000800010001000437012Q000800010012EB3Q00023Q001243000100034Q00313Q000200012Q00583Q00013Q0012EB3Q00043Q0012242Q0100058Q0002000100124Q00063Q00122Q000100078Q0002000100064Q001600010001000437012Q001600012Q00D300025Q001251000200083Q00122Q000200023Q00122Q000300096Q000400016Q0002000400012Q00583Q00017Q00033Q00030F3Q00687562422Q6F74737472612Q706564030B3Q00736F6674436C65616E7570030D3Q006C61756E63684D61786948756200084Q009C7Q00124Q00013Q00124Q00028Q0001000100124Q00038Q00019Q008Q00017Q00043Q0003053Q007063612Q6C030D3Q006C61756E63684D61786948756203043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012EB3Q00013Q0012EB000100024Q00FC3Q000200010006F23Q000900010001000437012Q000900010012EB000200033Q001243000300044Q0084010400014Q00400102000400012Q00583Q00017Q00", GetFEnv(), ...);
