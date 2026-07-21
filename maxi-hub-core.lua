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
				if (Enum <= 181) then
					if (Enum <= 90) then
						if (Enum <= 44) then
							if (Enum <= 21) then
								if (Enum <= 10) then
									if (Enum <= 4) then
										if (Enum <= 1) then
											if (Enum == 0) then
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
										elseif (Enum <= 2) then
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
										elseif (Enum > 3) then
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
									elseif (Enum <= 7) then
										if (Enum <= 5) then
											if (Inst[2] < Stk[Inst[4]]) then
												VIP = VIP + 1;
											else
												VIP = Inst[3];
											end
										elseif (Enum == 6) then
											local A = Inst[2];
											do
												return Unpack(Stk, A, A + Inst[3]);
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
										end
									elseif (Enum <= 8) then
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
									elseif (Enum > 9) then
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
								elseif (Enum <= 15) then
									if (Enum <= 12) then
										if (Enum > 11) then
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
											Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
										end
									elseif (Enum <= 13) then
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
									elseif (Enum > 14) then
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
								elseif (Enum <= 18) then
									if (Enum <= 16) then
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
									elseif (Enum > 17) then
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
									end
								elseif (Enum <= 19) then
									if (Stk[Inst[2]] <= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 20) then
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
							elseif (Enum <= 32) then
								if (Enum <= 26) then
									if (Enum <= 23) then
										if (Enum > 22) then
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
										end
									elseif (Enum <= 24) then
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
									elseif (Enum == 25) then
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
									end
								elseif (Enum <= 29) then
									if (Enum <= 27) then
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
									elseif (Enum == 28) then
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
								elseif (Enum <= 30) then
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
								elseif (Enum > 31) then
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
							elseif (Enum <= 38) then
								if (Enum <= 35) then
									if (Enum <= 33) then
										for Idx = Inst[2], Inst[3] do
											Stk[Idx] = nil;
										end
									elseif (Enum > 34) then
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
								elseif (Enum <= 36) then
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
								elseif (Enum > 37) then
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
							elseif (Enum <= 41) then
								if (Enum <= 39) then
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
								elseif (Enum > 40) then
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
								end
							elseif (Enum <= 42) then
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
							elseif (Enum > 43) then
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
							else
								local A = Inst[2];
								local B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Stk[Inst[4]]];
							end
						elseif (Enum <= 67) then
							if (Enum <= 55) then
								if (Enum <= 49) then
									if (Enum <= 46) then
										if (Enum == 45) then
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
									elseif (Enum <= 47) then
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
									elseif (Enum == 48) then
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
									end
								elseif (Enum <= 52) then
									if (Enum <= 50) then
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
									elseif (Enum > 51) then
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
								elseif (Enum <= 53) then
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
								elseif (Enum > 54) then
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
							elseif (Enum <= 61) then
								if (Enum <= 58) then
									if (Enum <= 56) then
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
									elseif (Enum == 57) then
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
								elseif (Enum <= 59) then
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
								elseif (Enum > 60) then
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
							elseif (Enum <= 64) then
								if (Enum <= 62) then
									local A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
								elseif (Enum > 63) then
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
								end
							elseif (Enum <= 65) then
								Stk[Inst[2]] = Stk[Inst[3]];
							elseif (Enum > 66) then
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
						elseif (Enum <= 78) then
							if (Enum <= 72) then
								if (Enum <= 69) then
									if (Enum == 68) then
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
								elseif (Enum <= 70) then
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
								elseif (Enum > 71) then
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
								end
							elseif (Enum <= 75) then
								if (Enum <= 73) then
									local A = Inst[2];
									local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
									local Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								elseif (Enum == 74) then
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
								end
							elseif (Enum <= 76) then
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
							elseif (Enum == 77) then
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
							else
								local A = Inst[2];
								local T = Stk[A];
								for Idx = A + 1, Inst[3] do
									Insert(T, Stk[Idx]);
								end
							end
						elseif (Enum <= 84) then
							if (Enum <= 81) then
								if (Enum <= 79) then
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
								elseif (Enum == 80) then
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
								end
							elseif (Enum <= 82) then
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
							elseif (Enum == 83) then
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
							else
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 87) then
							if (Enum <= 85) then
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
							elseif (Enum > 86) then
								local A = Inst[2];
								local B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
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
						elseif (Enum <= 88) then
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
						elseif (Enum > 89) then
							Stk[Inst[2]]();
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
					elseif (Enum <= 135) then
						if (Enum <= 112) then
							if (Enum <= 101) then
								if (Enum <= 95) then
									if (Enum <= 92) then
										if (Enum == 91) then
											do
												return;
											end
										else
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
										end
									elseif (Enum <= 93) then
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
									elseif (Enum > 94) then
										local A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
									else
										local A = Inst[2];
										Stk[A] = Stk[A]();
									end
								elseif (Enum <= 98) then
									if (Enum <= 96) then
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
									elseif (Enum > 97) then
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
									end
								elseif (Enum <= 99) then
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
								elseif (Enum > 100) then
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
							elseif (Enum <= 106) then
								if (Enum <= 103) then
									if (Enum == 102) then
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
								elseif (Enum <= 104) then
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
								elseif (Enum == 105) then
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
								else
									local A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							elseif (Enum <= 109) then
								if (Enum <= 107) then
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
								elseif (Enum == 108) then
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
							elseif (Enum <= 110) then
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
							elseif (Enum == 111) then
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
								do
									return Stk[Inst[2]];
								end
							end
						elseif (Enum <= 123) then
							if (Enum <= 117) then
								if (Enum <= 114) then
									if (Enum == 113) then
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
								elseif (Enum <= 115) then
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
								elseif (Enum > 116) then
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
							elseif (Enum <= 120) then
								if (Enum <= 118) then
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
								elseif (Enum > 119) then
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
							elseif (Enum <= 121) then
								if (Stk[Inst[2]] > Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = VIP + Inst[3];
								end
							elseif (Enum > 122) then
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
						elseif (Enum <= 129) then
							if (Enum <= 126) then
								if (Enum <= 124) then
									if (Inst[2] <= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 125) then
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
								else
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
								end
							elseif (Enum <= 127) then
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
							elseif (Enum == 128) then
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
							end
						elseif (Enum <= 132) then
							if (Enum <= 130) then
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							elseif (Enum == 131) then
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
						elseif (Enum <= 133) then
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
						elseif (Enum == 134) then
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
					elseif (Enum <= 158) then
						if (Enum <= 146) then
							if (Enum <= 140) then
								if (Enum <= 137) then
									if (Enum == 136) then
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
									end
								elseif (Enum <= 138) then
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
									Stk[Inst[2]][Inst[3]] = Inst[4];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Env[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								elseif (Enum == 139) then
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
							elseif (Enum <= 143) then
								if (Enum <= 141) then
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
								elseif (Enum == 142) then
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
							elseif (Enum <= 144) then
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
							elseif (Enum == 145) then
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
						elseif (Enum <= 152) then
							if (Enum <= 149) then
								if (Enum <= 147) then
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
								elseif (Enum == 148) then
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
							elseif (Enum <= 150) then
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
							elseif (Enum == 151) then
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
						elseif (Enum <= 155) then
							if (Enum <= 153) then
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
							elseif (Enum == 154) then
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
								Env[Inst[3]] = Stk[Inst[2]];
							end
						elseif (Enum <= 156) then
							local A = Inst[2];
							do
								return Stk[A], Stk[A + 1];
							end
						elseif (Enum > 157) then
							Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
						else
							Stk[Inst[2]] = Upvalues[Inst[3]];
						end
					elseif (Enum <= 169) then
						if (Enum <= 163) then
							if (Enum <= 160) then
								if (Enum > 159) then
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
								else
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
								end
							elseif (Enum <= 161) then
								if (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 162) then
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
							end
						elseif (Enum <= 166) then
							if (Enum <= 164) then
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
							elseif (Enum > 165) then
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
							else
								Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
							end
						elseif (Enum <= 167) then
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
						elseif (Enum == 168) then
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
						end
					elseif (Enum <= 175) then
						if (Enum <= 172) then
							if (Enum <= 170) then
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
							elseif (Enum == 171) then
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
						elseif (Enum <= 173) then
							Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
						elseif (Enum > 174) then
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
					elseif (Enum <= 178) then
						if (Enum <= 176) then
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
						elseif (Enum > 177) then
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
					elseif (Enum <= 179) then
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
					elseif (Enum == 180) then
						Stk[Inst[2]] = Stk[Inst[3]] * Inst[4];
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
					end
				elseif (Enum <= 272) then
					if (Enum <= 226) then
						if (Enum <= 203) then
							if (Enum <= 192) then
								if (Enum <= 186) then
									if (Enum <= 183) then
										if (Enum == 182) then
											if (Stk[Inst[2]] < Stk[Inst[4]]) then
												VIP = Inst[3];
											else
												VIP = VIP + 1;
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
											Stk[Inst[2]] = Env[Inst[3]];
										end
									elseif (Enum <= 184) then
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
									elseif (Enum == 185) then
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
									end
								elseif (Enum <= 189) then
									if (Enum <= 187) then
										Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
									elseif (Enum > 188) then
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
										Stk[Inst[2]] = Stk[Inst[3]] / Inst[4];
									end
								elseif (Enum <= 190) then
									Stk[Inst[2]] = Stk[Inst[3]] - Inst[4];
								elseif (Enum == 191) then
									do
										return Stk[Inst[2]]();
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
							elseif (Enum <= 197) then
								if (Enum <= 194) then
									if (Enum > 193) then
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
								elseif (Enum <= 195) then
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
								elseif (Enum > 196) then
									Stk[Inst[2]] = Stk[Inst[3]] * Stk[Inst[4]];
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
							elseif (Enum <= 200) then
								if (Enum <= 198) then
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
								elseif (Enum == 199) then
									Stk[Inst[2]] = Env[Inst[3]];
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
							elseif (Enum <= 201) then
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
							elseif (Enum > 202) then
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
							elseif (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 214) then
							if (Enum <= 208) then
								if (Enum <= 205) then
									if (Enum > 204) then
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
								elseif (Enum <= 206) then
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
								elseif (Enum > 207) then
									local B = Inst[3];
									local K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
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
							elseif (Enum <= 211) then
								if (Enum <= 209) then
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
								elseif (Enum > 210) then
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
								end
							elseif (Enum <= 212) then
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
							elseif (Enum > 213) then
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
						elseif (Enum <= 220) then
							if (Enum <= 217) then
								if (Enum <= 215) then
									local A = Inst[2];
									Stk[A](Stk[A + 1]);
								elseif (Enum > 216) then
									local B;
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
									A = Inst[2];
									B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
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
										if (Mvm[1] == 65) then
											Indexes[Idx - 1] = {Stk,Mvm[3]};
										else
											Indexes[Idx - 1] = {Upvalues,Mvm[3]};
										end
										Lupvals[#Lupvals + 1] = Indexes;
									end
									Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
								end
							elseif (Enum <= 218) then
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
							elseif (Enum > 219) then
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
						elseif (Enum <= 223) then
							if (Enum <= 221) then
								Stk[Inst[2]] = not Stk[Inst[3]];
							elseif (Enum > 222) then
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
							end
						elseif (Enum <= 224) then
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
						elseif (Enum == 225) then
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
					elseif (Enum <= 249) then
						if (Enum <= 237) then
							if (Enum <= 231) then
								if (Enum <= 228) then
									if (Enum == 227) then
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
								elseif (Enum <= 229) then
									local A = Inst[2];
									local T = Stk[A];
									local B = Inst[3];
									for Idx = 1, B do
										T[Idx] = Stk[A + Idx];
									end
								elseif (Enum > 230) then
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
									Stk[Inst[2]] = Stk[Inst[3]] % Inst[4];
								end
							elseif (Enum <= 234) then
								if (Enum <= 232) then
									local A = Inst[2];
									local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
									local Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								elseif (Enum == 233) then
									if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
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
								end
							elseif (Enum <= 235) then
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
							elseif (Enum > 236) then
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
							end
						elseif (Enum <= 243) then
							if (Enum <= 240) then
								if (Enum <= 238) then
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
								elseif (Enum > 239) then
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
							elseif (Enum <= 241) then
								Stk[Inst[2]] = {};
							elseif (Enum > 242) then
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
						elseif (Enum <= 246) then
							if (Enum <= 244) then
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
							elseif (Enum == 245) then
								VIP = Inst[3];
							else
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
							end
						elseif (Enum <= 247) then
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
						elseif (Enum > 248) then
							Stk[Inst[2]][Inst[3]] = Inst[4];
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
					elseif (Enum <= 260) then
						if (Enum <= 254) then
							if (Enum <= 251) then
								if (Enum > 250) then
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
							elseif (Enum <= 252) then
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
							elseif (Enum == 253) then
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Top));
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
							end
						elseif (Enum <= 257) then
							if (Enum <= 255) then
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
							elseif (Enum > 256) then
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
							else
								Stk[Inst[2]] = Stk[Inst[3]] - Stk[Inst[4]];
							end
						elseif (Enum <= 258) then
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
						elseif (Enum == 259) then
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
					elseif (Enum <= 266) then
						if (Enum <= 263) then
							if (Enum <= 261) then
								local A = Inst[2];
								local Results = {Stk[A](Stk[A + 1])};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum > 262) then
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
							else
								Stk[Inst[2]] = #Stk[Inst[3]];
							end
						elseif (Enum <= 264) then
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
						elseif (Enum > 265) then
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
					elseif (Enum <= 269) then
						if (Enum <= 267) then
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
						elseif (Enum == 268) then
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
					elseif (Enum <= 270) then
						if (Stk[Inst[2]] < Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum == 271) then
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
					elseif (Inst[2] < Stk[Inst[4]]) then
						VIP = Inst[3];
					else
						VIP = VIP + 1;
					end
				elseif (Enum <= 318) then
					if (Enum <= 295) then
						if (Enum <= 283) then
							if (Enum <= 277) then
								if (Enum <= 274) then
									if (Enum == 273) then
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
								elseif (Enum <= 275) then
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
								elseif (Enum == 276) then
									local A;
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
							elseif (Enum <= 280) then
								if (Enum <= 278) then
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
								elseif (Enum == 279) then
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
							elseif (Enum <= 281) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Top)));
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum > 282) then
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
							end
						elseif (Enum <= 289) then
							if (Enum <= 286) then
								if (Enum <= 284) then
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
								elseif (Enum == 285) then
									if (Stk[Inst[2]] == Stk[Inst[4]]) then
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
							elseif (Enum <= 287) then
								local A = Inst[2];
								do
									return Unpack(Stk, A, Top);
								end
							elseif (Enum > 288) then
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
							elseif Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 292) then
							if (Enum <= 290) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A]());
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum == 291) then
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
							end
						elseif (Enum <= 293) then
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
						elseif (Enum > 294) then
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
					elseif (Enum <= 306) then
						if (Enum <= 300) then
							if (Enum <= 297) then
								if (Enum == 296) then
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
							elseif (Enum <= 298) then
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
							elseif (Enum > 299) then
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
							end
						elseif (Enum <= 303) then
							if (Enum <= 301) then
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
							elseif (Enum == 302) then
								if (Stk[Inst[2]] <= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
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
						elseif (Enum <= 304) then
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
						elseif (Enum > 305) then
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
					elseif (Enum <= 312) then
						if (Enum <= 309) then
							if (Enum <= 307) then
								local A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
							elseif (Enum == 308) then
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
							end
						elseif (Enum <= 310) then
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
						elseif (Enum > 311) then
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
						elseif not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 315) then
						if (Enum <= 313) then
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
						elseif (Enum == 314) then
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
					elseif (Enum <= 316) then
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
					elseif (Enum > 317) then
						local B = Stk[Inst[4]];
						if not B then
							VIP = VIP + 1;
						else
							Stk[Inst[2]] = B;
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
				elseif (Enum <= 341) then
					if (Enum <= 329) then
						if (Enum <= 323) then
							if (Enum <= 320) then
								if (Enum == 319) then
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
							elseif (Enum <= 321) then
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
							elseif (Enum > 322) then
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
								A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							end
						elseif (Enum <= 326) then
							if (Enum <= 324) then
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
							elseif (Enum == 325) then
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
							elseif (Stk[Inst[2]] < Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 327) then
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
						elseif (Enum > 328) then
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
						else
							Upvalues[Inst[3]] = Stk[Inst[2]];
						end
					elseif (Enum <= 335) then
						if (Enum <= 332) then
							if (Enum <= 330) then
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
							elseif (Enum == 331) then
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 333) then
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
						elseif (Enum == 334) then
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
					elseif (Enum <= 338) then
						if (Enum <= 336) then
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Top));
							end
						elseif (Enum == 337) then
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
					elseif (Enum <= 339) then
						local B;
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
						A = Inst[2];
						B = Stk[Inst[3]];
						Stk[A + 1] = B;
						Stk[A] = B[Inst[4]];
					elseif (Enum > 340) then
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
					end
				elseif (Enum <= 352) then
					if (Enum <= 346) then
						if (Enum <= 343) then
							if (Enum > 342) then
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
							end
						elseif (Enum <= 344) then
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
						elseif (Enum == 345) then
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
					elseif (Enum <= 349) then
						if (Enum <= 347) then
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
						elseif (Enum > 348) then
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
					elseif (Enum <= 350) then
						local B = Stk[Inst[4]];
						if B then
							VIP = VIP + 1;
						else
							Stk[Inst[2]] = B;
							VIP = Inst[3];
						end
					elseif (Enum == 351) then
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
				elseif (Enum <= 358) then
					if (Enum <= 355) then
						if (Enum <= 353) then
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
						elseif (Enum == 354) then
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
					elseif (Enum <= 356) then
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
					elseif (Enum > 357) then
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
						local A = Inst[2];
						local Results, Limit = _R(Stk[A](Stk[A + 1]));
						Top = (Limit + A) - 1;
						local Edx = 0;
						for Idx = A, Top do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					end
				elseif (Enum <= 361) then
					if (Enum <= 359) then
						Stk[Inst[2]] = Inst[3] ~= 0;
					elseif (Enum == 360) then
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
				elseif (Enum <= 362) then
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
				elseif (Enum == 363) then
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
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!67012Q00030C3Q005343524950545F5449544C4503083Q004D4158492048554203083Q004755495F4E414D4503073Q004D617869487562030D3Q0054454C454752414D5F4C494E4B03153Q00682Q7470733A2Q2F742E6D652F4D4158495F48554203073Q00506C617965727303043Q0067616D65030A3Q0047657453657276696365030A3Q0052756E5365727669636503103Q0055736572496E70757453657276696365030A3Q0047756953657276696365030B3Q00482Q747053657276696365030C3Q0054772Q656E5365727669636503113Q005265706C69636174656453746F72616765030B3Q00434F4E4649475F46494C4503143Q006D6178692D6875622D636F6E6669672E6A736F6E030F3Q0053452Q4C5F53544154455F46494C4503183Q006D6178692D6875622D73652Q6C2D73746174652E6A736F6E030B3Q004B45595F574542482Q4F4B03793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D6803133Q00444953434F52445F434F4E4649475F46494C4503153Q006D6178692D6875622D646973636F72642E6A736F6E03123Q0055736572446973636F7264576562682Q6F6B034Q0003153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E75746573026Q00244003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F7003063Q00706C6179657203093Q00706C6179657247756903043Q0067656E7603063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47030C3Q00656E73757265506C61796572030B3Q004661726D456E61626C6564030A3Q006661726D54687265616403093Q006661726D52756E4964028Q00030D3Q006661726D54696D65546F74616C030F3Q006661726D54696D655374617274656403123Q0074656C65706F7274436F2Q6E656374696F6E03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503093Q006661726D506861736503043Q0069646C65030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403063Q00484F544B455903043Q00456E756D03073Q004B6579436F64652Q033Q00456E64030F3Q0070656E64696E675072657653746F70030B3Q004D61786948756253746F70030E3Q006661726D436865636B506175736503123Q0073686F756C644661726D436F6E74696E7565030D3Q00697343616E63656C452Q726F7203103Q0063616D657261436F2Q6E656374696F6E030E3Q00612Q706C79496E7669736963616D030E3Q0073746F7043616D6572614C2Q6F70030D3Q00726573746F726543616D657261030F3Q00737461727443616D6572614C2Q6F70030E3Q00434F2Q4C4543545F524144495553026Q004E40030E3Q0054656C65706F7274486569676874027Q004003133Q0053746F6E6554656C65706F7274486569676874026Q000C40030C3Q0069676E6F72656444726F7073030F3Q0063616368656444726F70436F756E7403043Q00564B5F46025Q0080514003073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D417454617267657403113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A65026Q00494003113Q00426C6F636B65645A6F6E6543656E74657203153Q00626C6F636B65645A6F6E6556697375616C5061727403133Q00424C4F434B45445F5A4F4E455F464F4C444552030C3Q004D6178694875625A6F6E6573030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C026Q003440030F3Q0053652Q6C4261746368416D6F756E74025Q004CCD4003143Q0053652Q6C436F636F6E75745468726573686F6C64024Q008093C140030D3Q0053452Q4C5F574F524C445F4944022Q008081CBE4E941030D3Q004641524D5F574F524C445F4944022Q00105C7A23F24103123Q0053452Q4C5F574149545F41465445525F5450026Q001440030A3Q0053452Q4C5F4954454D5303073Q004176616361646F03073Q00436F636F6E757403093Q00436163616F4265616E03053Q00412Q706C6503043Q00436F726E03053Q004C656D6F6E03113Q0073652Q73696F6E53746F6E6544726F707303113Q0073652Q73696F6E54722Q65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E6564030C3Q006661726D5761726E696E6773030D3Q006C6173745761726E696E67417403103Q0073652Q73696F6E54722Q6544726F7073030D3Q004F726269744469616D65746572026Q002C40030A3Q004F7262697453702Q6564029A5Q99F13F030E3Q0044454641554C545F55495F504F5303053Q005544696D322Q033Q006E6577026Q003040026Q00E03F025Q00E070C0030A3Q0073617665645569506F73030C3Q007363722Q656E477569526566030A3Q0068692Q64656E4775697303133Q00736166654D6F6465436F2Q6E656374696F6E73030B3Q0054524144455F48494E545303053Q00747261646503073Q0074726164696E67030A3Q0074726164656F2Q666572030C3Q0074726164657265717565737403083Q0065786368616E676503043Q0073776170030A3Q006F72626974416E676C6503093Q006D6F75736548656C64030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F7573655903103Q0063616E557365436F6E66696746696C6503133Q0073617665436F6E6669675363686564756C6564030C3Q006D61696E4672616D65526566030A3Q0073617665436F6E66696703123Q007363686564756C6553617665436F6E666967030D3Q006C6F616453652Q6C537461746503133Q0068617350656E64696E6753652Q6C5374617465030D3Q007361766553652Q6C5374617465030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F6703123Q0066696E616C697A6553652Q6C526573756D6503103Q006578656375746553652Q6C4974656D73031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F747374726170030A3Q006C6F6164436F6E666967030F3Q00707573684661726D5761726E696E6703103Q00636C6561724661726D5761726E696E6703133Q006765744661726D5761726E696E67735465787403183Q0067657454656C65706F7274486569676874466F724B696E64030F3Q006765744661726D4D6F646554657874030F3Q00535455434B5F465F5345434F4E4453026Q001040030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365030B3Q00736561726368416E676C65030C3Q00736561726368526164697573026Q005440030C3Q00706174726F6C506F696E7473030B3Q00706174726F6C496E646578026Q00F03F030B3Q00687562506F736974696F6E030C3Q004855425F574149545F4D494E026Q000840030C3Q004855425F574149545F4D4158026Q002040030F3Q004855425F4E4541525F524144495553026Q002E40030F3Q006C61737453652Q6C436865636B4174030E3Q0073652Q6C496E50726F6772652Q73030F3Q006D616E75616C53652Q6C546F6B656E03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006765744661726D446973636F7264576562682Q6F6B03113Q0073617665446973636F7264436F6E666967030A3Q0050484153455F5445585403103Q00D0BED0B6D0B8D0B4D0B0D0BDD0B8D0B503063Q00736561726368030A3Q00D0BFD0BED0B8D181D0BA03043Q006D696E65030C3Q00D0B4D0BED0B1D18BD187D0B003043Q007761697403133Q00D0B6D0B4D191D0BC20D0B4D180D0BED0BFD18B03073Q00636F2Q6C65637403083Q00D181D0B1D0BED18003043Q0073652Q6C030E3Q00D0BFD180D0BED0B4D0B0D0B6D0B02Q033Q00687562030A3Q00D186D0B5D0BDD182D18003143Q0067657454656C65706F7274537061776E5061727403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C030B3Q0072656C65617365464B657903103Q0072656C656173654D6F757365486F6C6403133Q0073746F704368617261637465724D6F74696F6E03163Q00676574426C6F636B65645A6F6E6548616C6653697A6503143Q00676574426C6F636B65645A6F6E654D696E4D617803123Q006973506F73496E426C6F636B65645A6F6E6503133Q0069734E6F6465496E426C6F636B65645A6F6E6503173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00757064617465426C6F636B65645A6F6E6556697375616C03163Q00736574426C6F636B65645A6F6E654174506C61796572030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C655761697403183Q00696E74652Q7275707469626C6557616974466F7253652Q6C03123Q0063617074757265487562506F736974696F6E030E3Q00676574487562506F736974696F6E03093Q0069734E656172487562030D3Q0074656C65706F7274546F487562030B3Q00687562526573745761697403143Q0072657475726E546F48756241667465724E6F6465030C3Q0073686F756C645072652Q734603063Q007072652Q7346030B3Q00686F6C644D6F757365417403073Q00636C69636B4174030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73030F3Q0067657450617274506F736974696F6E030F3Q0067657441696D5363722Q656E506F73030B3Q0069734E6F6465416C697665030D3Q006765744E6F64654865616C7468030A3Q0072657365744175746F46030B3Q007570646174654175746F46030B3Q00676574486974626F786573030E3Q00676574436F2Q6C65637450617274030D3Q006765744E6F646543656E746572030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473030E3Q007069636B4265737454617267657403133Q0072656275696C64506174726F6C506F696E7473030E3Q0074656C65706F727453656172636803103Q0044524F505F4D4F44454C5F48494E545303093Q00462Q6F644D6F64656C03123Q00572Q6F645265736F75726365734D6F64656C03143Q00436F2Q7065725265736F75726365734D6F64656C03123Q004C6561665265736F75726365734D6F64656C030E3Q005265736F75726365734D6F64656C03133Q0069735265736F7572636544726F704D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C030D3Q00697344726F7049676E6F72656403113Q006D61726B44726F70436F2Q6C656374656403123Q00697356616C6964436F2Q6C65637444726F7003173Q0066696E6443616D6572615265736F7572636544726F7073030D3Q0066696E6444726F70734E656172030B3Q00636F2Q6C65637450617274030F3Q00636F2Q6C656374412Q6C44726F7073030A3Q00612Q7461636B50617274030F3Q0064726F707341726553652Q746C656403103Q0077616974416E645363616E44726F707303103Q006765744D696E65416E63686F72506F7303103Q0074656C65706F7274546F54617267657403083Q0069734F7572477569030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A656374030A3Q007363616E547261646573030D3Q00686964654F7468657247756973030A3Q00636C6561725461626C65030C3Q0073746F70536166654D6F6465030D3Q007374617274536166654D6F646503123Q006765745265736F7572636573466F6C64657203113Q006765745265736F75726365416D6F756E7403143Q0067657453652Q6C5472692Q676572416D6F756E74030D3Q006E2Q6564734175746F53652Q6C030E3Q006765744661726D5365636F6E6473030B3Q00682Q74705265717565737403123Q00706F7374446973636F7264576562682Q6F6B03103Q0073656E64446973636F7264456D62656403173Q006765745265736F75726365734F7665724F6E655465787403153Q0067657453652Q73696F6E53746174734669656C647303153Q006C6F674661726D53652Q73696F6E446973636F726403133Q0077616974466F7243686172616374657248727003083Q0073652Q6C57616974030D3Q0067657453652Q6C52656D6F746503163Q00676574576F726C6454656C65706F727452656D6F7465030D3Q00776F726C6454656C65706F727403103Q0073652Q6C5265736F757263654974656D030C3Q0072756E53652Q6C4379636C65030B3Q0072756E4175746F53652Q6C030D3Q0072756E4D616E75616C53652Q6C03103Q006D6179626552756E4175746F53652Q6C03123Q006D6179626552756E4661726D5265706F7274030E3Q0072756E5365617263685068617365030D3Q006B692Q6C4661726D4C2Q6F707303083Q0073746F704661726D030B3Q00736F6674436C65616E7570030A3Q0066752Q6C556E6C6F616403093Q0073746172744661726D030F3Q004D617869487562476574537461747303183Q004D6178694875625061757365466F72496E76656E746F7279031B3Q004D617869487562526573756D654166746572496E76656E746F727903113Q005F4D61786948756255494C69627261727903083Q007265616466696C6503063Q00697366696C6503063Q0069706169727303183Q006D6178692D6875622F6D6178692D6875622D75692E6C7561030F3Q006D6178692D6875622D75692E6C756103053Q00652Q726F72035E3Q005B4D415849204855425D20D09DD183D0B6D0B5D0BD206D6178692D6875622D75692E6C756120D0B220776F726B7370616365206578656375746F722028D180D18FD0B4D0BED0BC20D181D0BE20D181D0BAD180D0B8D0BFD182D0BED0BC29030A3Q006C6F6164737472696E6703103Q00406D6178692D6875622D75692E6C756103173Q005B4D415849204855425D20554920636F6D70696C653A2003083Q00746F737472696E6703133Q005B4D415849204855425D2055492072756E3A20030C3Q004D61786948756255494C696203093Q0055495F4C41594F555403073Q0050414E454C5F57026Q00694003073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58026Q006B4003063Q00524F57335F59026Q006C4003063Q0046552Q4C5F57025Q00407A40030E3Q00534C494445525F50414E454C5F48026Q006440030E3Q0053452Q53494F4E5F424F44595F59025Q00804140030D3Q00534C494445525F424F44595F59026Q004440030A3Q004D494E455F424F585F48025Q00C06540030D3Q00534C49444552535F424F585F48026Q005C40030A3Q00534146455F424F585F48026Q005640030D3Q00544F2Q474C455F595F53544550026Q004640030D3Q00534C494445525F595F5354455003163Q006275696C644D61786948756243726564697473546162030F3Q00687562422Q6F74737472612Q70656403103Q00622Q6F7473747261704D617869487562030D3Q006C61756E63684D617869487562030F3Q004D61786948756252656C61756E636803083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C6179657247756903053Q007072696E7403283Q005B4D415849204855425D20D0BCD0BED0B4D183D0BBD18C20D0B7D0B0D0B3D180D183D0B6D0B5D0BD03043Q007461736B03053Q00646566657200E4022Q0012933Q00023Q00124Q00013Q00124Q00043Q00124Q00033Q00124Q00063Q00124Q00053Q00124Q00083Q00206Q000900122Q000200078Q0002000200124Q00073Q00124Q00083Q00206Q000900122Q0002000A8Q0002000200124Q000A3Q00124Q00083Q00206Q000900122Q0002000B8Q0002000200124Q000B3Q00124Q00083Q00206Q000900122Q0002000C8Q0002000200124Q000C3Q00124Q00083Q00206Q000900122Q0002000D8Q0002000200124Q000D3Q00124Q00083Q00206Q000900122Q0002000E8Q0002000200124Q000E3Q00124Q00083Q00206Q000900122Q0002000F8Q0002000200124Q000F3Q00124Q00113Q00124Q00103Q00124Q00133Q00124Q00123Q00124Q00153Q00124Q00143Q00124Q00173Q00124Q00163Q00124Q00193Q00124Q00188Q00013Q00124Q001A3Q00124Q001C3Q00124Q001B8Q00013Q00124Q001D8Q00013Q00124Q001E9Q003Q00124Q001F9Q003Q00124Q00209Q003Q00124Q00213Q00124Q00223Q00122Q000100238Q0002000200264Q004A000100240004F53Q004A00010012C73Q00234Q005E3Q0001000200129B3Q00213Q0004F53Q004C00010012C73Q00253Q00129B3Q00213Q00020B7Q0012E43Q00269Q003Q00124Q00279Q003Q00124Q00283Q00124Q002A3Q00124Q00293Q00124Q002A3Q00124Q002B3Q00124Q002A3Q00129B3Q002C4Q00567Q00124Q002D9Q003Q00124Q002E9Q003Q00124Q002F3Q00124Q00313Q00124Q00303Q00124Q00333Q00124Q00323Q0012543Q002A3Q0012B83Q00343Q00124Q002A3Q00124Q00353Q00124Q00373Q00206Q003800206Q003900124Q00369Q003Q00124Q003A3Q00124Q00223Q0012C7000100213Q00208200010001003B2Q0033012Q000200020026CA3Q0075000100240004F53Q007500010012C73Q00213Q0020825Q003B00129B3Q003A4Q0067016Q00129B3Q003C3Q00020B3Q00013Q00129B3Q003D3Q00020B3Q00023Q00129B3Q003E4Q00217Q00129B3Q003F3Q00020B3Q00033Q00129B3Q00403Q00020B3Q00043Q00129B3Q00413Q00020B3Q00053Q00129B3Q00423Q00020B3Q00063Q00129A3Q00433Q00124Q00453Q00124Q00443Q00124Q00473Q00124Q00463Q00124Q00493Q00124Q00489Q003Q00124Q004A3Q00124Q002A3Q00124Q004B3Q00124Q004D3Q00124Q004C8Q00013Q00124Q004E8Q00013Q00124Q004F9Q003Q00124Q00508Q00013Q00124Q00518Q00013Q00124Q00528Q00013Q00124Q00538Q00013Q00124Q00549Q003Q00124Q00559Q003Q00124Q00569Q003Q00124Q00573Q00124Q00593Q00124Q00589Q003Q00124Q005A9Q003Q00124Q005B3Q00124Q005D3Q00124Q005C8Q00013Q00124Q005E3Q00124Q00603Q00124Q005F3Q00124Q00623Q00124Q00613Q00124Q00643Q00124Q00633Q00124Q00663Q00124Q00653Q00124Q00683Q00124Q00673Q00124Q006A3Q00124Q00698Q00063Q00122Q0001006C3Q00122Q0002006D3Q00122Q0003006E3Q00122Q0004006F3Q00122Q000500703Q00122Q000600718Q0006000100129B3Q006B3Q0012503Q002A3Q00124Q00723Q00124Q002A3Q00124Q00733Q00124Q002A3Q00124Q00749Q003Q00124Q00759Q003Q00124Q00763Q0012543Q002A3Q0012813Q00773Q00124Q00793Q00124Q00783Q00124Q007B3Q00124Q007A3Q00124Q007D3Q00206Q007E00122Q0001002A3Q00122Q0002007F3Q00122Q000300803Q001254000400814Q0051012Q0004000200124Q007C9Q003Q00124Q00829Q003Q00124Q00839Q003Q00124Q00849Q003Q00124Q00854Q00F13Q00063Q0012F6000100873Q00122Q000200883Q00122Q000300893Q00122Q0004008A3Q00122Q0005008B3Q00122Q0006008C8Q0006000100129B3Q00863Q001261012Q002A3Q00124Q008D9Q003Q00124Q008E3Q00124Q002A3Q00122Q0001002A3Q00122Q000100903Q00124Q008F3Q00020B3Q00073Q0012453Q00919Q003Q00124Q00929Q003Q00124Q00933Q00020B3Q00083Q00129B3Q00943Q00020B3Q00093Q00129B3Q00953Q00020B3Q000A3Q00129B3Q00963Q00020B3Q000B3Q00129B3Q00973Q00020B3Q000C3Q00129B3Q00983Q00020B3Q000D3Q00129B3Q00993Q00020B3Q000E3Q00129B3Q009A3Q00020B3Q000F3Q00129B3Q009B3Q00020B3Q00103Q00129B3Q009C3Q00020B3Q00113Q00129B3Q009D3Q00020B3Q00123Q00129B3Q009E3Q00020B3Q00133Q00129B3Q009F3Q00020B3Q00143Q00129B3Q00A03Q00020B3Q00153Q00129B3Q00A13Q00020B3Q00163Q00129B3Q00A23Q00020B3Q00173Q001226012Q00A33Q00124Q00A53Q00124Q00A49Q003Q00124Q00A69Q003Q00124Q00A73Q00124Q002A3Q00124Q00A83Q00124Q002A3Q00129B3Q00A93Q001209012Q00AB3Q00124Q00AA9Q003Q00124Q00AC3Q00124Q00AE3Q00124Q00AD9Q003Q00124Q00AF3Q00124Q00B13Q00124Q00B03Q0012543Q00B33Q001264012Q00B23Q00124Q00B53Q00124Q00B43Q00124Q002A3Q00124Q00B69Q003Q00124Q00B73Q00124Q002A3Q00124Q00B83Q00124Q002A3Q00129B3Q00B93Q0012C73Q001B3Q0020B45Q004500129B3Q00BA3Q00020B3Q00183Q00129B3Q00BB3Q00020B3Q00193Q0012AE3Q00BC9Q00000700304Q003300BE00304Q00BF00C000304Q00C100C200304Q00C300C400304Q00C500C600304Q00C700C800304Q00C900CA00124Q00BD3Q00020B3Q001A3Q00129B3Q00CB4Q00217Q00129B3Q00CC3Q0012C73Q00CD3Q00020B0001001B4Q00D73Q0002000100020B3Q001C3Q00129B3Q00CE3Q00020B3Q001D3Q00129B3Q00CF3Q00020B3Q001E3Q00129B3Q00D03Q00020B3Q001F3Q00129B3Q00D13Q00020B3Q00203Q00129B3Q00D23Q00020B3Q00213Q00129B3Q00D33Q00020B3Q00223Q00129B3Q00D43Q00020B3Q00233Q00129B3Q00D53Q00020B3Q00243Q00129B3Q00D63Q00020B3Q00253Q00129B3Q00D73Q00020B3Q00263Q00129B3Q00D83Q00020B3Q00273Q00129B3Q00D93Q00020B3Q00283Q00129B3Q00DA3Q00020B3Q00293Q00129B3Q00DB3Q00020B3Q002A3Q00129B3Q00DC3Q00020B3Q002B3Q00129B3Q00DD3Q00020B3Q002C3Q00129B3Q00DE3Q00020B3Q002D3Q00129B3Q00DF3Q00020B3Q002E3Q00129B3Q00E03Q00020B3Q002F3Q00129B3Q00E13Q00020B3Q00303Q00129B3Q00E23Q00020B3Q00313Q00129B3Q00E33Q00020B3Q00323Q00129B3Q00E43Q00020B3Q00333Q00129B3Q00E53Q00020B3Q00343Q00129B3Q00E63Q00020B3Q00353Q00129B3Q00E73Q00020B3Q00363Q00129B3Q00E83Q00020B3Q00373Q00129B3Q00E93Q00020B3Q00383Q00129B3Q00EA3Q00020B3Q00393Q00129B3Q00EB3Q00020B3Q003A3Q00129B3Q00EC3Q00020B3Q003B3Q00129B3Q00ED3Q00020B3Q003C3Q00129B3Q00EE3Q00020B3Q003D3Q00129B3Q00EF3Q00020B3Q003E3Q00129B3Q00F03Q00020B3Q003F3Q00129B3Q00F13Q00020B3Q00403Q00129B3Q00F23Q00020B3Q00413Q00129B3Q00F33Q00020B3Q00423Q00129B3Q00F43Q00020B3Q00433Q00124Q00F58Q00053Q00122Q000100F73Q00122Q000200F83Q00122Q000300F93Q00122Q000400FA3Q00122Q000500FB8Q0005000100129B3Q00F63Q00020B3Q00443Q00129B3Q00FC3Q00020B3Q00453Q00129B3Q00FD3Q00020B3Q00463Q00129B3Q00FE3Q00020B3Q00473Q00129B3Q00FF3Q00020B3Q00483Q00129B4Q00012Q00020B3Q00493Q00129B3Q002Q012Q00020B3Q004A3Q00129B3Q0002012Q00020B3Q004B3Q00129B3Q0003012Q00020B3Q004C3Q00129B3Q0004012Q00020B3Q004D3Q00129B3Q0005012Q00020B3Q004E3Q00129B3Q0006012Q00020B3Q004F3Q00129B3Q0007012Q00020B3Q00503Q00129B3Q0008012Q00020B3Q00513Q00129B3Q0009012Q00020B3Q00523Q00129B3Q000A012Q00020B3Q00533Q00129B3Q000B012Q00020B3Q00543Q00129B3Q000C012Q00020B3Q00553Q00129B3Q000D012Q00020B3Q00563Q00129B3Q000E012Q00020B3Q00573Q00129B3Q000F012Q00020B3Q00583Q00129B3Q0010012Q00020B3Q00593Q00129B3Q0011012Q00020B3Q005A3Q00129B3Q0012012Q00020B3Q005B3Q00129B3Q0013012Q00020B3Q005C3Q00129B3Q0014012Q00020B3Q005D3Q00129B3Q0015012Q00020B3Q005E3Q00129B3Q0016012Q00020B3Q005F3Q00129B3Q0017012Q00020B3Q00603Q00129B3Q0018012Q00020B3Q00613Q00129B3Q0019012Q00020B3Q00623Q00129B3Q001A012Q00020B3Q00633Q00129B3Q001B012Q00020B3Q00643Q00129B3Q001C012Q00020B3Q00653Q00129B3Q001D012Q00020B3Q00663Q00129B3Q001E012Q00020B3Q00673Q00129B3Q001F012Q00020B3Q00683Q00129B3Q0020012Q00020B3Q00693Q00129B3Q0021012Q00020B3Q006A3Q00129B3Q0022012Q00020B3Q006B3Q00129B3Q0023012Q00020B3Q006C3Q00129B3Q0024012Q00020B3Q006D3Q00129B3Q0025012Q00020B3Q006E3Q00129B3Q0026012Q00020B3Q006F3Q00129B3Q0027012Q00020B3Q00703Q00129B3Q0028012Q00020B3Q00713Q00129B3Q0029012Q00020B3Q00723Q00129B3Q002A012Q00020B3Q00733Q00129B3Q002B012Q00020B3Q00743Q001204012Q002C012Q00124Q00213Q00122Q0001002B012Q00104Q003B000100124Q003A3Q00064Q001902013Q0004F53Q001902010012C73Q003A3Q0012C70001002B012Q0006E93Q0019020100010004F53Q001902010012C73Q00CD3Q0012C70001003A4Q00D73Q000200012Q00217Q00129B3Q003A3Q00020B3Q00753Q00129B3Q002D012Q0012C73Q00213Q0012540001002E012Q00020B000200764Q00AD3Q000100020012C73Q00213Q0012540001002F012Q00020B000200774Q00AD3Q000100020012C73Q00213Q00125400010030012Q00020B000200784Q005A012Q0001000200124Q00223Q00122Q000100238Q0002000200264Q0032020100240004F53Q003202010012C73Q00234Q005E3Q00010002000637012Q0033020100010004F53Q003302010012C73Q00253Q00125400010031013Q002C00013Q00010006372Q010075020100010004F53Q007502012Q0021000100013Q0012C7000200223Q0012C700030032013Q00330102000200020026CA00020055020100240004F53Q005502010012C7000200223Q0012C700030033013Q00330102000200020026CA00020055020100240004F53Q005502010012C700020034013Q00F1000300023Q00125400040035012Q00125400050036013Q00E50003000200012Q00050102000200040004F53Q005302010012C700070033013Q0041000800064Q00330107000200020006200107005302013Q0004F53Q005302010012C700070032013Q0041000800064Q00330107000200022Q0041000100073Q0004F53Q0055020100066300020049020100020004F53Q004902010006372Q01005A020100010004F53Q005A02010012C700020037012Q00125400030038013Q00D70002000200010012C700020039013Q0041000300013Q0012540004003A013Q00E800020004000300063701020067020100010004F53Q006702010012C700040037012Q00126B0005003B012Q00122Q0006003C015Q000700036Q0006000200024Q0005000500064Q0004000200010012C7000400CD4Q0041000500024Q000501040002000500063701040073020100010004F53Q007302010012C700060037012Q00126B0007003D012Q00122Q0008003C015Q000900056Q0008000200024Q0007000700084Q00060002000100125400060031013Q00AD3Q000600050012C73Q00223Q0012C7000100234Q0033012Q000200020026CA3Q007E020100240004F53Q007E02010012C73Q00234Q005E3Q00010002000637012Q007F020100010004F53Q007F02010012C73Q00253Q00125400010031013Q0039014Q000100124Q003E019Q000D00122Q00010040012Q00122Q00020041017Q0001000200122Q00010042012Q00122Q00020041017Q0001000200122Q00010043012Q0012D600020044017Q0001000200122Q00010045012Q00122Q00020046017Q0001000200122Q00010047012Q00122Q00020048017Q0001000200122Q00010049012Q00122Q0002004A013Q004D012Q0001000200122Q0001004B012Q00122Q0002004C017Q0001000200122Q0001004D012Q00122Q0002004E017Q0001000200122Q0001004F012Q00122Q00020050017Q0001000200125400010051012Q0012D600020052017Q0001000200122Q00010053012Q00122Q00020054017Q0001000200122Q00010055012Q00122Q00020056017Q0001000200122Q00010057012Q00122Q000200454Q00AD3Q0001000200129B3Q003F012Q00020B3Q00793Q00129B3Q0058013Q0067016Q00129B3Q0059012Q00020B3Q007A3Q00129B3Q005A012Q00020B3Q007B3Q00129B3Q005B012Q0012C73Q00213Q0012540001005C012Q00020B0002007C4Q00AD3Q000100020012C73Q001F3Q000620012Q00BD02013Q0004F53Q00BD02010012C73Q00203Q000637012Q00DB020100010004F53Q00DB02010012C73Q00083Q0012540002005D013Q002B5Q00022Q0033012Q00020002000637012Q00C9020100010004F53Q00C902010012C73Q00083Q0012EF0001005E019Q000100122Q0002005F019Q00026Q000200010012C73Q00073Q00125400010060013Q002C5Q0001000637012Q00D4020100010004F53Q00D402010012C73Q00073Q00122500010061019Q000100122Q0002005F019Q00026Q0002000200129B3Q001F3Q0012623Q001F3Q00122Q00020062019Q000200122Q00020063017Q0002000200124Q00203Q0012C73Q0064012Q0012CB00010065017Q0002000100124Q0066012Q00122Q00010067019Q000100020B0001007D4Q00D73Q000200012Q005B3Q00013Q007E3Q00143Q0003063Q00706C6179657203093Q00706C6179657247756903063Q00506172656E7403043Q0067616D6503083Q0049734C6F6164656403063Q004C6F6164656403043Q005761697403073Q00506C6179657273030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030E3Q0046696E6446697273744368696C6403093Q00506C61796572477569030C3Q0057616974466F724368696C64026Q003E40030E3Q004D6178694875624B65794761746503073Q0044657374726F7903043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C0003053Q007063612Q6C00443Q0012C73Q00013Q000620012Q000C00013Q0004F53Q000C00010012C73Q00023Q000620012Q000C00013Q0004F53Q000C00010012C73Q00023Q0020825Q0003000620012Q000C00013Q0004F53Q000C00012Q0067012Q00014Q00703Q00023Q0012C73Q00043Q0020575Q00052Q0033012Q00020002000637012Q0015000100010004F53Q001500010012C73Q00043Q0020825Q00060020575Q00072Q00D73Q000200010012C73Q00083Q0020825Q0009000637012Q001E000100010004F53Q001E00010012C7000100083Q00208200010001000A0020570001000100072Q00332Q01000200022Q00413Q00013Q00129B3Q00013Q0012A7000100013Q00202Q00010001000B00122Q0003000C6Q00010003000200122Q000100023Q00122Q000100023Q00062Q0001002D000100010004F53Q002D00010012C7000100013Q0020312Q010001000D00122Q0003000C3Q00122Q0004000E6Q00010004000200122Q000100023Q0012C7000100023Q0006372Q010032000100010004F53Q003200012Q00672Q016Q0070000100023Q0012C7000100023Q00205700010001000B0012540003000F4Q006A0001000300020006202Q01003A00013Q0004F53Q003A00010020570002000100102Q00D70002000200010012C7000200113Q0020820002000200120026CA00020041000100130004F53Q004100010012C7000200143Q00020B00036Q00D70002000200012Q0067010200014Q0070000200024Q005B3Q00013Q00013Q00043Q0003043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646500053Q0012913Q00013Q00122Q000100033Q00202Q00010001000400104Q000200016Q00017Q00033Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964030E3Q006661726D436865636B5061757365010D3Q0012C7000100013Q0006202Q01000B00013Q0004F53Q000B00010012C7000100023Q00061D012Q0009000100010004F53Q000900010012C7000100034Q00DD000100013Q0004F53Q000B00012Q005800016Q00672Q0100014Q0070000100024Q005B3Q00017Q00083Q0003063Q00747970656F6603063Q00737472696E6703053Q006C6F77657203043Q0066696E6403063Q0063616E63656C026Q00F03F0003073Q0063616E63652Q6C01213Q0012C7000100014Q004100026Q00332Q01000200020026A100010007000100020004F53Q000700012Q00672Q016Q0070000100023Q0012C7000100023Q0020C00001000100034Q00028Q00010002000200122Q000200023Q00202Q0002000200044Q000300013Q00122Q000400053Q00122Q000500066Q000600016Q00020006000200262Q0002001E000100070004F53Q001E00010012C7000200023Q00200C0002000200044Q000300013Q00122Q000400083Q00122Q000500066Q000600016Q00020006000200262Q0002001E000100070004F53Q001E00012Q005800026Q0067010200014Q0070000200024Q005B3Q00017Q00013Q0003053Q007063612Q6C00043Q0012C73Q00013Q00020B00016Q00D73Q000200012Q005B3Q00013Q00013Q00043Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q00456E756D03093Q00496E7669736963616D00063Q00124D3Q00013Q00122Q000100033Q00202Q00010001000200202Q00010001000400104Q000200016Q00017Q00023Q0003103Q0063616D657261436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400093Q0012C73Q00013Q000620012Q000800013Q0004F53Q000800010012C73Q00013Q0020575Q00022Q00D73Q000200012Q00217Q00129B3Q00014Q005B3Q00017Q00023Q00030E3Q0073746F7043616D6572614C2Q6F7003053Q007063612Q6C00063Q0012C73Q00014Q005A3Q000100010012C73Q00023Q00020B00016Q00D73Q000200012Q005B3Q00013Q00013Q00063Q0003063Q00706C6179657203163Q0044657643616D6572614F2Q636C7573696F6E4D6F646503043Q0067656E7603153Q004D61786948756243616D6572614F726967696E616C03043Q00456E756D03043Q005A2Q6F6D000A3Q0012C73Q00013Q0012C7000100033Q0020820001000100040006372Q010008000100010004F53Q000800010012C7000100053Q0020820001000100020020820001000100060010783Q000200012Q005B3Q00017Q00063Q00030E3Q0073746F7043616D6572614C2Q6F70030E3Q00612Q706C79496E7669736963616D03103Q0063616D657261436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374000B3Q0012FA3Q00018Q0001000100124Q00028Q0001000100124Q00043Q00206Q000500206Q000600122Q000200028Q0002000200124Q00038Q00017Q00053Q0003063Q00747970656F6603093Q00777269746566696C6503083Q0066756E6374696F6E03083Q007265616466696C6503063Q00697366696C6500133Q0012C73Q00013Q0012C7000100024Q0033012Q000200020026CA3Q000F000100030004F53Q000F00010012C73Q00013Q0012C7000100044Q0033012Q000200020026CA3Q000F000100030004F53Q000F00010012C73Q00013Q0012C7000100054Q0033012Q000200020026A13Q0010000100030004F53Q001000012Q00588Q0067012Q00014Q00703Q00024Q005B3Q00017Q00243Q0003103Q0063616E557365436F6E66696746696C65030E3Q0054656C65706F727448656967687403133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A6503113Q00426C6F636B65645A6F6E6543656E74657203013Q005803013Q005903013Q005A030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F70030C3Q006D61696E4672616D6552656603083Q00506F736974696F6E03083Q005569585363616C6503053Q005363616C6503093Q005569584F2Q6673657403063Q004F2Q6673657403083Q005569595363616C6503093Q005569594F2Q6673657403053Q007063612Q6C005D3Q0012C73Q00014Q005E3Q00010002000637012Q0005000100010004F53Q000500012Q005B3Q00014Q00F15Q00140012E1000100023Q00104Q0002000100122Q000100033Q00104Q0003000100122Q000100043Q00104Q0004000100122Q000100053Q00104Q0005000100122Q000100063Q00104Q000600010012C7000100073Q0010FE3Q0007000100122Q000100083Q00104Q0008000100122Q000100093Q00104Q000900010012EA0001000A3Q00104Q000A000100122Q0001000B3Q00104Q000B000100122Q0001000C3Q00104Q000C000100122Q0001000D3Q00104Q000D000100122Q0001000E3Q00104Q000E000100122Q0001000F3Q00104Q000F000100122Q000100103Q00104Q0010000100122Q000100113Q00062Q0001003100013Q0004F53Q003100012Q00F1000100033Q00124F010200113Q00202Q00020002001200122Q000300113Q00202Q00030003001300122Q000400113Q00202Q0004000400144Q0001000300010006372Q010032000100010004F53Q003200012Q0021000100013Q0010783Q001100010012EA000100153Q00104Q0015000100122Q000100163Q00104Q0016000100122Q000100173Q00104Q0017000100122Q000100183Q00104Q0018000100122Q000100193Q00104Q0019000100122Q0001001A3Q00104Q001A000100122Q0001001B3Q00104Q001B000100122Q0001001C3Q00062Q0001005200013Q0004F53Q005200010012C70001001C3Q00207700010001001D00202Q00020001001200202Q00020002001F00104Q001E000200202Q00020001001200202Q00020002002100104Q0020000200202Q00020001001300202Q00020002001F00104Q0022000200202Q00020001001300202Q00020002002100104Q002300020012C7000100243Q0006D800023Q000100012Q00418Q00052Q01000200020006202Q01005C00013Q0004F53Q005C00010012C7000300243Q0006D800040001000100012Q00413Q00024Q00D70003000200012Q005B3Q00013Q00023Q00023Q00030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500063Q0012873Q00013Q00206Q00024Q00029Q0000029Q008Q00017Q00023Q0003093Q00777269746566696C65030B3Q00434F4E4649475F46494C4500053Q0012963Q00013Q00122Q000100026Q00029Q00000200016Q00017Q00043Q0003133Q0073617665436F6E6669675363686564756C656403043Q007461736B03053Q0064656C6179026Q00D03F000C3Q0012C73Q00013Q000620012Q000400013Q0004F53Q000400012Q005B3Q00014Q0067012Q00013Q00129B3Q00013Q0012C73Q00023Q0020825Q0003001254000100043Q00020B00026Q005F3Q000200012Q005B3Q00013Q00013Q00023Q0003133Q0073617665436F6E6669675363686564756C6564030A3Q0073617665436F6E66696700054Q00667Q00124Q00013Q00124Q00028Q000100016Q00017Q00073Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C65030B3Q0070656E64696E6753652Q6C001C3Q0012C73Q00014Q005E3Q00010002000620012Q000900013Q0004F53Q000900010012C73Q00023Q0012C7000100034Q0033012Q00020002000637012Q000B000100010004F53Q000B00012Q00218Q00703Q00023Q0012C73Q00043Q00020B00016Q0005012Q00020001000620012Q001900013Q0004F53Q001900010012C7000200054Q0041000300014Q00330102000200020026CA00020019000100060004F53Q001900010020820002000100070006200102001900013Q0004F53Q001900012Q0070000100024Q0021000200024Q0070000200024Q005B3Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030F3Q0053452Q4C5F53544154455F46494C4500083Q0012193Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00023Q00030D3Q006C6F616453652Q6C53746174652Q00083Q0012C73Q00014Q005E3Q000100020026CA3Q0005000100020004F53Q000500012Q00588Q0067012Q00014Q00703Q00024Q005B3Q00017Q00093Q0003103Q0063616E557365436F6E66696746696C65030B3Q0070656E64696E6753652Q6C2Q0103053Q00706861736503063Q006D616E75616C030A3Q00726573756D654661726D03073Q007361766564417403043Q007469636B03053Q007063612Q6C02203Q0006372Q010004000100010004F53Q000400012Q00F100026Q0041000100023Q0012C7000200014Q005E00020001000200063701020009000100010004F53Q000900012Q005B3Q00014Q00F100023Q00050030F9000200020003001078000200043Q0020820003000100050026A100030010000100030004F53Q001000012Q005800036Q0067010300013Q0010780002000500030020820003000100060026A100030016000100030004F53Q001600012Q005800036Q0067010300013Q00109200020006000300122Q000300086Q00030001000200102Q00020007000300122Q000300093Q0006D800043Q000100012Q00413Q00024Q00D70003000200012Q005B3Q00013Q00013Q00043Q0003093Q00777269746566696C65030F3Q0053452Q4C5F53544154455F46494C45030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646500083Q0012A83Q00013Q00122Q000100023Q00122Q000200033Q00202Q0002000200044Q00048Q000200049Q0000016Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503053Q007063612Q6C00093Q0012C73Q00014Q005E3Q00010002000637012Q0005000100010004F53Q000500012Q005B3Q00013Q0012C73Q00023Q00020B00016Q00D73Q000200012Q005B3Q00013Q00013Q00073Q0003063Q00697366696C65030F3Q0053452Q4C5F53544154455F46494C4503093Q00777269746566696C65030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465030B3Q0070656E64696E6753652Q6C012Q000E3Q0012C73Q00013Q0012C7000100024Q0033012Q00020002000620012Q000D00013Q0004F53Q000D00010012C73Q00033Q00122B2Q0100023Q00122Q000200043Q00202Q0002000200054Q00043Q000100302Q0004000600074Q000200049Q0000012Q005B3Q00017Q00013Q0003053Q007063612Q6C01093Q000637012Q0004000100010004F53Q000400012Q00F100016Q00413Q00013Q0012C7000100013Q0006D800023Q000100012Q00418Q00D70001000200012Q005B3Q00013Q00013Q00083Q0003053Q00666F72636503153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003153Q006C6F674661726D53652Q73696F6E446973636F726403213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B0023Q00E081386E4103103Q00446973636F72644C6F674F6E53652Q6C00184Q009D7Q0020825Q0001000620012Q001000013Q0004F53Q001000010012C73Q00023Q000620012Q001700013Q0004F53Q001700010012C73Q00034Q005E3Q000100020026A13Q0017000100040004F53Q001700010012C73Q00053Q001254000100063Q001254000200074Q005F3Q000200010004F53Q001700010012C73Q00083Q000620012Q001700013Q0004F53Q001700010012C73Q00053Q001254000100063Q001254000200074Q005F3Q000200012Q005B3Q00017Q00053Q00030E3Q00636C65617253652Q6C537461746503123Q0073656E6453652Q6C446973636F72644C6F67030A3Q00726573756D654661726D03043Q007461736B03053Q006465666572020E3Q001231000200016Q00020001000100122Q000200026Q00038Q00020002000100202Q00023Q000300062Q0002000C00013Q0004F53Q000C00010012C7000200043Q00208200020002000500020B00036Q00D70002000200012Q0070000100024Q005B3Q00013Q00013Q00043Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D00113Q0012C73Q00013Q000637012Q0010000100010004F53Q001000012Q0067012Q00013Q00129B3Q00023Q0012C73Q00033Q000620012Q000C00013Q0004F53Q000C00010012C73Q00034Q00672Q0100014Q0067010200014Q005F3Q000200012Q0067016Q00129B3Q00023Q0012C73Q00044Q005A3Q000100012Q005B3Q00017Q00063Q0003063Q00697061697273030A3Q0053452Q4C5F4954454D5303103Q0073652Q6C5265736F757263654974656D029A5Q99B93F03043Q007461736B03043Q0077616974022B4Q00E300025Q00122Q000300013Q00122Q000400026Q00030002000500044Q002700010006202Q01000C00013Q0004F53Q000C00012Q0041000800014Q005E0008000100020006370108000C000100010004F53Q000C00010004F53Q002900010012C7000800034Q0041000900074Q00330108000200020006200108001200013Q0004F53Q001200012Q0067010200013Q0012C7000800024Q0006010800083Q00060E0106001F000100080004F53Q001F0001000620012Q001F00013Q0004F53Q001F00012Q004100085Q001254000900044Q003301080002000200063701080027000100010004F53Q002700010004F53Q002900010004F53Q002700010012C7000800024Q0006010800083Q00060E01060027000100080004F53Q002700010012C7000800053Q002082000800080006001254000900044Q00D700080002000100066300030005000100020004F53Q000500012Q0070000200024Q005B3Q00017Q00033Q00030D3Q006C6F616453652Q6C537461746503043Q007461736B03053Q00737061776E000E3Q0012C73Q00014Q005E3Q00010002000637012Q0006000100010004F53Q000600012Q00672Q016Q0070000100023Q0012C7000100023Q0020820001000100030006D800023Q000100012Q00418Q00D70001000200012Q00672Q0100014Q0070000100024Q005B3Q00013Q00013Q001D3Q00030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0073652Q6C03053Q00666F72636503063Q006D616E75616C2Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303053Q007068617365032A3Q00D092D0BED0B7D0BED0B1D0BDD0BED0B2D0BBD18FD0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E03133Q0077616974466F72436861726163746572487270026Q00284003043Q007461736B03043Q007761697403123Q0053452Q4C5F574149545F41465445525F545003203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D73030D3Q007361766553652Q6C537461746503063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q00776F726C6454656C65706F7274030D3Q004641524D5F574F524C445F4944027Q0040030D3Q006C6F616453652Q6C537461746503123Q0066696E616C697A6553652Q6C526573756D6503243Q00D097D0B0D0B2D0B5D180D188D0B0D0B5D0BC20D0BFD180D0BED0B4D0B0D0B6D1833Q2E026Q00F03F030E3Q00636C65617253652Q6C537461746503043Q0069646C6500673Q0012C73Q00013Q000620012Q000400013Q0004F53Q000400012Q005B3Q00014Q0067012Q00013Q0012DE3Q00013Q00124Q00033Q00124Q00029Q0000034Q00015Q00202Q00010001000500262Q0001000E000100060004F53Q000E00012Q005800016Q00672Q0100013Q0010783Q000400012Q009D00015Q0020820001000100070026A100010015000100060004F53Q001500012Q005800016Q00672Q0100013Q0010783Q0007000100020B00015Q0010783Q000800010006D800010001000100012Q00418Q009D00025Q0020820002000200090026CA0002004D000100030004F53Q004D00012Q0041000200013Q0012D40003000A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q000200020001002Q120002000D3Q00202Q00020002000E00122Q0003000F6Q0002000200014Q000200013Q00122Q000300106Q00020002000100122Q000200113Q00020B000300023Q00020B000400034Q007300020004000200122Q000300123Q00122Q000400136Q00058Q0003000500014Q000300013Q00122Q000400146Q00030002000100122Q000300153Q00122Q000400166Q00030002000100122Q0003000B3Q00122Q0004000C6Q00030002000100122Q0003000D3Q00202Q00030003000E00122Q000400176Q00030002000100122Q000300186Q00030001000200062Q0003006200013Q0004F53Q006200010020820004000300090026CA00040062000100130004F53Q006200010012C7000400194Q004100056Q0041000600024Q005F0004000600010004F53Q006200012Q009D00025Q0020820002000200090026CA00020060000100130004F53Q006000012Q0041000200013Q0012D40003001A6Q00020002000100122Q0002000B3Q00122Q0003000C6Q0002000200010012610002000D3Q00202Q00020002000E00122Q0003001B6Q00020002000100122Q000200196Q00038Q000400016Q00020004000100044Q006200010012C70002001C4Q005A0002000100012Q006701025Q00129B000200013Q0012540002001D3Q00129B000200024Q005B3Q00013Q00043Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q0012C7000100013Q0006202Q01000900013Q0004F53Q000900010012C7000100013Q0020820001000100020006202Q01000900013Q0004F53Q000900010012C7000100013Q001078000100034Q005B3Q00017Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q009D00015Q0020820001000100010006202Q01000900013Q0004F53Q000900010012C7000100024Q009D00025Q0020820002000200012Q004100036Q005F0001000300012Q005B3Q00017Q00023Q0003043Q007461736B03043Q007761697401073Q0012CC000100013Q00202Q0001000100024Q00028Q0001000200014Q000100016Q000100028Q00017Q00013Q00030E3Q0073652Q6C496E50726F6772652Q7300033Q0012C73Q00014Q00703Q00024Q005B3Q00017Q00363Q0003103Q0063616E557365436F6E66696746696C6503063Q00697366696C65030B3Q00434F4E4649475F46494C4503053Q007063612Q6C03063Q00747970656F6603053Q007461626C6503093Q004661726D54722Q657300030A3Q004661726D53746F6E6573030E3Q0054656C65706F727448656967687403063Q006E756D62657203133Q0053746F6E6554656C65706F727448656967687403073Q00557365464B657903083Q00557365436C69636B030C3Q004F72626974456E61626C6564030B3Q0041696D4174546172676574030A3Q004F7262697453702Q6564030D3Q004F726269744469616D6574657203113Q00426C6F636B5569447572696E674661726D030B3Q00426C6F636B547261646573030E3Q0048756257616974456E61626C6564030D3Q004175746F53746172744661726D030E3Q0052656A6F696E4175746F4C6F616403133Q00426C6F636B65645A6F6E6573456E61626C6564030F3Q00426C6F636B65645A6F6E6553697A6503043Q006D61746803053Q00636C616D7003053Q00666C2Q6F72026Q003440026Q005E4003113Q00426C6F636B65645A6F6E6543656E746572026Q00084003073Q00566563746F72332Q033Q006E6577026Q00F03F027Q0040030F3Q004175746F53652Q6C456E61626C656403113Q0053652Q6C436865636B496E74657276616C03123Q0055736572446973636F7264576562682Q6F6B03063Q00737472696E6703153Q00446973636F72645265706F727473456E61626C656403143Q00446973636F72645265706F72744D696E7574657303143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003103Q00446973636F72644C6F674F6E53652Q6C03103Q00446973636F72644C6F674F6E53746F7003083Q005569595363616C65030A3Q0073617665645569506F7303053Q005544696D3203083Q005569585363616C65028Q0003093Q005569584F2Q66736574026Q00304003093Q005569594F2Q6673657400D63Q0012C73Q00014Q005E3Q00010002000620012Q000900013Q0004F53Q000900010012C73Q00023Q0012C7000100034Q0033012Q00020002000637012Q000A000100010004F53Q000A00012Q005B3Q00013Q0012C73Q00043Q00020B00016Q0005012Q00020001000620012Q001400013Q0004F53Q001400010012C7000200054Q0041000300014Q00330102000200020026A100020015000100060004F53Q001500012Q005B3Q00013Q0020820002000100070026CA0002001B000100080004F53Q001B00010020820002000100090026A10002001B000100080004F53Q001B00010012C7000200053Q00208200030001000A2Q00330102000200020026CA000200220001000B0004F53Q0022000100208200020001000A00129B0002000A3Q0012C7000200053Q00208200030001000C2Q00330102000200020026CA000200290001000B0004F53Q0029000100208200020001000C00129B0002000C3Q00208200020001000D0026A10002002E000100080004F53Q002E000100208200020001000D00129B0002000D3Q00208200020001000E0026A100020033000100080004F53Q0033000100208200020001000E00129B0002000E3Q00208200020001000F0026A100020038000100080004F53Q0038000100208200020001000F00129B0002000F3Q0020820002000100100026A10002003D000100080004F53Q003D000100208200020001001000129B000200103Q0012C7000200053Q0020820003000100112Q00330102000200020026CA000200440001000B0004F53Q0044000100208200020001001100129B000200113Q0012C7000200053Q0020820003000100122Q00330102000200020026CA0002004B0001000B0004F53Q004B000100208200020001001200129B000200123Q0020820002000100130026A100020050000100080004F53Q0050000100208200020001001300129B000200133Q0020820002000100140026A100020055000100080004F53Q0055000100208200020001001400129B000200143Q0020820002000100150026A10002005A000100080004F53Q005A000100208200020001001500129B000200153Q0020820002000100160026A10002005F000100080004F53Q005F000100208200020001001600129B000200163Q0020820002000100170026A100020064000100080004F53Q0064000100208200020001001700129B000200173Q0020820002000100180026A100020069000100080004F53Q0069000100208200020001001800129B000200183Q0012C7000200053Q0020820003000100192Q00330102000200020026CA000200780001000B0004F53Q007800010012C70002001A3Q0020C200020002001B00122Q0003001A3Q00202Q00030003001C00202Q0004000100194Q00030002000200122Q0004001D3Q00122Q0005001E6Q00020005000200122Q000200193Q0012C7000200053Q00208200030001001F2Q00330102000200020026CA0002008B000100060004F53Q008B000100208200020001001F2Q0006010200023Q000E7C0020008B000100020004F53Q008B00010012C7000200213Q0020E000020002002200202Q00030001001F00202Q00030003002300202Q00040001001F00202Q00040004002400202Q00050001001F00202Q0005000500204Q00020005000200122Q0002001F3Q0020820002000100250026A100020090000100080004F53Q0090000100208200020001002500129B000200253Q0012C7000200053Q0020820003000100262Q00330102000200020026CA000200970001000B0004F53Q0097000100208200020001002600129B000200263Q0012C7000200053Q0020820003000100272Q00330102000200020026CA0002009E000100280004F53Q009E000100208200020001002700129B000200273Q0020820002000100290026A1000200A3000100080004F53Q00A3000100208200020001002900129B000200293Q0012C7000200053Q00208200030001002A2Q00330102000200020026CA000200B50001000B0004F53Q00B500010012C70002001A3Q0020C200020002001B00122Q0003001A3Q00202Q00030003001C00202Q00040001002A4Q00030002000200122Q000400233Q00122Q0005001E6Q00020005000200122Q0002002A3Q0012C70002002A3Q0020B400020002002C00129B0002002B3Q00208200020001002D0026A1000200BA000100080004F53Q00BA000100208200020001002D00129B0002002D3Q00208200020001002E0026A1000200BF000100080004F53Q00BF000100208200020001002E00129B0002002E3Q0012C7000200053Q00208200030001002F2Q00330102000200020026CA000200D50001000B0004F53Q00D500010012C7000200313Q002082000200020022002082000300010032000637010300CA000100010004F53Q00CA0001001254000300333Q002082000400010034000637010400CE000100010004F53Q00CE0001001254000400353Q00208200050001002F002082000600010036000637010600D3000100010004F53Q00D30001001254000600334Q006A00020006000200129B000200304Q005B3Q00013Q00013Q00043Q00030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65030B3Q00434F4E4649475F46494C4500083Q0012193Q00013Q00206Q000200122Q000200033Q00122Q000300046Q000200039Q009Q008Q00017Q00043Q0003043Q007469636B030D3Q006C6173745761726E696E674174025Q00804640030C3Q006661726D5761726E696E677302113Q001243010200016Q00020001000200122Q000300026Q000300033Q00062Q0003000C00013Q0004F53Q000C00010012C7000300024Q002C000300035Q000103000200030026460103000C000100030004F53Q000C00012Q005B3Q00013Q0012C7000300024Q00AD00033Q00020012C7000300044Q00AD00033Q00012Q005B3Q00017Q00023Q00030C3Q006661726D5761726E696E67730001033Q0012C7000100013Q0020BB00013Q00022Q005B3Q00017Q00083Q0003053Q007061697273030C3Q006661726D5761726E696E677303053Q007461626C6503063Q00696E7365727403043Q00E280A22003043Q00736F727403063Q00636F6E63617403013Q000A00194Q00377Q00122Q000100013Q00122Q000200026Q00010002000300044Q000C00010012C7000600033Q00207E0006000600044Q00075Q00122Q000800056Q000900056Q0008000800094Q00060008000100066300010005000100020004F53Q000500010012C7000100033Q0020112Q01000100064Q00028Q00010002000100122Q000100033Q00202Q0001000100074Q00025Q00122Q000300086Q000100036Q00019Q0000017Q00033Q0003053Q0073746F6E6503133Q0053746F6E6554656C65706F7274486569676874030E3Q0054656C65706F727448656967687401073Q0026CA3Q0004000100010004F53Q000400010012C7000100024Q0070000100023Q0012C7000100034Q0070000100024Q005B3Q00017Q00063Q00030F3Q0063616368656454722Q65436F756E74028Q00030E3Q00D0B4D0B5D180D0B5D0B2D18CD18F03103Q0063616368656453746F6E65436F756E74030A3Q00D0BAD0B0D0BCD0BDD0B8030A3Q00D0BFD0BED0B8D181D0BA000D3Q0012C73Q00013Q000E050002000500013Q0004F53Q000500010012543Q00034Q00703Q00023Q0012C73Q00043Q000E050002000A00013Q0004F53Q000A00010012543Q00054Q00703Q00023Q0012543Q00064Q00703Q00024Q005B3Q00017Q00033Q0003123Q0055736572446973636F7264576562682Q6F6B034Q00030B3Q004B45595F574542482Q4F4B000B3Q0012C73Q00013Q000620012Q000800013Q0004F53Q000800010012C73Q00013Q0026A13Q0008000100020004F53Q000800010012C73Q00014Q00703Q00023Q0012C73Q00034Q00703Q00024Q005B3Q00017Q00023Q0003103Q0063616E557365436F6E66696746696C6503123Q007363686564756C6553617665436F6E66696700083Q0012C73Q00014Q005E3Q00010002000637012Q0005000100010004F53Q000500012Q005B3Q00013Q0012C73Q00024Q005A3Q000100012Q005B3Q00017Q00093Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030E3Q00576F726C6454656C65706F727473030B3Q0054656C65706F7274506164030D3Q0054656C65706F72744D6F64656C2Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734100293Q0012803Q00013Q00206Q000200122Q000200038Q0002000200064Q0008000100010004F53Q000800012Q0021000100014Q0070000100023Q00205700013Q0002001254000300044Q006A0001000300020006372Q01000F000100010004F53Q000F00012Q0021000200024Q0070000200023Q002057000200010002001254000400054Q006A00020004000200063701020016000100010004F53Q001600012Q0021000300034Q0070000300023Q002057000300020002001254000500064Q006A0003000500020006370103001D000100010004F53Q001D00012Q0021000400044Q0070000400023Q002057000400030007001254000600084Q006A0004000600020006200104002300013Q0004F53Q002300012Q0070000300023Q002057000400030009001244000600086Q000700016Q000400076Q00049Q0000017Q00033Q0003133Q005669727475616C496E7075744D616E6167657203043Q0067616D65030A3Q004765745365727669636500063Q00123C012Q00023Q00206Q000300122Q000200018Q0002000200124Q00018Q00017Q00023Q0003133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00073Q0012C73Q00013Q000620012Q000600013Q0004F53Q000600010012C73Q00023Q00020B00016Q00D73Q000200012Q005B3Q00013Q00013Q00063Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D65000A3Q001217012Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00033Q0003093Q006D6F75736548656C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C00103Q0012C73Q00013Q000637012Q0004000100010004F53Q000400012Q005B3Q00013Q0012C73Q00023Q000620012Q000A00013Q0004F53Q000A00010012C73Q00033Q00020B00016Q00D73Q000200010012C73Q00033Q00020B000100014Q00D73Q000200012Q0067016Q00129B3Q00014Q005B3Q00013Q00023Q00063Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74030A3Q00686F6C644D6F75736558030A3Q00686F6C644D6F75736559028Q0003043Q0067616D65000A3Q0012A33Q00013Q00206Q000200122Q000200033Q00122Q000300043Q00122Q000400056Q00055Q00122Q000600063Q00122Q000700058Q000700016Q00017Q00033Q0003063Q00747970656F66030D3Q006D6F7573653172656C6561736503083Q0066756E6374696F6E00083Q0012C73Q00013Q0012C7000100024Q0033012Q000200020026CA3Q0007000100030004F53Q000700010012C73Q00024Q005A3Q000100012Q005B3Q00017Q00083Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900133Q0012C73Q00013Q0020825Q0002000620012Q000900013Q0004F53Q000900010012C73Q00013Q0020825Q00020020575Q0003001254000200044Q006A3Q00020002000637012Q000C000100010004F53Q000C00012Q005B3Q00013Q0012C7000100063Q0020162Q010001000700104Q0005000100122Q000100063Q00202Q00010001000700104Q000800016Q00017Q00023Q00030F3Q00426C6F636B65645A6F6E6553697A65027Q004000043Q0012C73Q00013Q0020BC5Q00022Q00703Q00024Q005B3Q00017Q00043Q0003113Q00426C6F636B65645A6F6E6543656E74657203163Q00676574426C6F636B65645A6F6E6548616C6653697A6503073Q00566563746F72332Q033Q006E657700193Q0012C73Q00013Q000637012Q0005000100010004F53Q000500012Q00213Q00014Q009C3Q00033Q0012C73Q00024Q006F3Q0001000200122Q000100013Q00122Q000200033Q00202Q0002000200044Q00038Q00048Q00058Q0002000500024Q00010001000200122Q000200013Q00122Q000300033Q00202Q0003000300044Q00048Q00058Q00068Q0003000600024Q0002000200034Q000100038Q00017Q00063Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403113Q00426C6F636B65645A6F6E6543656E74657203143Q00676574426C6F636B65645A6F6E654D696E4D617803013Q005803013Q005903013Q005A012E3Q0012C7000100013Q0006202Q01000800013Q0004F53Q00080001000620012Q000800013Q0004F53Q000800010012C7000100023Q0006372Q01000A000100010004F53Q000A00012Q00672Q016Q0070000100023Q0012C7000100034Q00880001000100020006202Q01001000013Q0004F53Q0010000100063701020012000100010004F53Q001200012Q006701036Q0070000300023Q00208200033Q00040020820004000100040006130004002A000100030004F53Q002A000100208200033Q00040020820004000200040006130003002A000100040004F53Q002A000100208200033Q00050020820004000100050006130004002A000100030004F53Q002A000100208200033Q00050020820004000200050006130003002A000100040004F53Q002A000100208200033Q00060020820004000100060006130004002A000100030004F53Q002A000100208200033Q000600208200040002000600067900030002000100040004F53Q002B00012Q005800036Q0067010300014Q0070000300024Q005B3Q00017Q00023Q00030D3Q006765744E6F646543656E74657203123Q006973506F73496E426C6F636B65645A6F6E65010A3Q0012C7000100014Q004100026Q00332Q010002000200065E01020008000100010004F53Q000800010012C7000200024Q0041000300014Q00330102000200022Q0070000200024Q005B3Q00017Q00083Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203083Q00496E7374616E63652Q033Q006E657703063Q00466F6C64657203043Q004E616D6503063Q00506172656E7400113Q0012423Q00013Q00206Q000200122Q000200038Q0002000200064Q000F000100010004F53Q000F00010012C7000100043Q0020A200010001000500122Q000200066Q0001000200026Q00013Q00122Q000100033Q00104Q0007000100122Q000100013Q00104Q000800012Q00703Q00024Q005B3Q00017Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403053Q007063612Q6C000C3Q0012C73Q00013Q000620012Q000800013Q0004F53Q000800010012C73Q00023Q00020B00016Q00D73Q000200012Q00217Q00129B3Q00013Q0012C73Q00023Q00020B000100014Q00D73Q000200012Q005B3Q00013Q00023Q00023Q0003153Q00626C6F636B65645A6F6E6556697375616C5061727403073Q0044657374726F7900043Q0012C73Q00013Q0020575Q00022Q00D73Q000200012Q005B3Q00017Q00043Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403133Q00424C4F434B45445F5A4F4E455F464F4C44455203073Q0044657374726F7900093Q00120C012Q00013Q00206Q000200122Q000200038Q0002000200064Q000800013Q0004F53Q0008000100205700013Q00042Q00D70001000200012Q005B3Q00017Q00203Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403113Q00426C6F636B65645A6F6E6543656E74657203183Q0064657374726F79426C6F636B65645A6F6E6556697375616C03173Q00656E73757265426C6F636B65645A6F6E65466F6C64657203153Q00626C6F636B65645A6F6E6556697375616C5061727403063Q00506172656E7403083Q00496E7374616E63652Q033Q006E657703043Q005061727403043Q004E616D65030A3Q00416E746954505A6F6E6503083Q00416E63686F7265642Q01030A3Q0043616E436F2Q6C696465010003083Q0043616E517565727903083Q0043616E546F756368030A3Q0043617374536861646F7703083Q004D6174657269616C03043Q00456E756D030A3Q00466F7263654669656C6403053Q00436F6C6F7203063Q00436F6C6F723303073Q0066726F6D524742025Q00E06F40025Q00805140030C3Q005472616E73706172656E6379020AD7A3703D0AE73F03043Q0053697A6503073Q00566563746F7233030F3Q00426C6F636B65645A6F6E6553697A6503063Q00434672616D6500453Q0012C73Q00013Q000620012Q000600013Q0004F53Q000600010012C73Q00023Q000637012Q0009000100010004F53Q000900010012C73Q00034Q005A3Q000100012Q005B3Q00013Q0012C73Q00044Q005E3Q000100020012C7000100053Q0006202Q01001200013Q0004F53Q001200010012C7000100053Q0020820001000100060006372Q010034000100010004F53Q003400010012C7000100073Q00202D2Q010001000800122Q000200096Q00010002000200122Q000100053Q00122Q000100053Q00302Q0001000A000B00122Q000100053Q00302Q0001000C000D00122Q000100053Q00302Q0001000E000F00122Q000100053Q00302Q00010010000F00122Q000100053Q00302Q00010011000F00122Q000100053Q00302Q00010012000F00122Q000100053Q00122Q000200143Q00202Q00020002001300202Q00020002001500102Q00010013000200122Q000100053Q00122Q000200173Q00202Q00020002001800122Q000300193Q00122Q0004001A3Q00122Q0005001A6Q00020005000200102Q00010016000200122Q000100053Q00302Q0001001B001C00122Q000100053Q00102Q000100063Q0012C7000100053Q0012C80002001E3Q00202Q00020002000800122Q0003001F3Q00122Q0004001F3Q00122Q0005001F6Q00020005000200102Q0001001D000200122Q000100053Q00122Q000200203Q00202Q00020002000800122Q000300026Q00020002000200102Q00010020000200122Q000100053Q00302Q0001001B001C6Q00017Q00083Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403113Q00426C6F636B65645A6F6E6543656E74657203083Q00506F736974696F6E03173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E66696700163Q0012C73Q00013Q0020825Q0002000620012Q000900013Q0004F53Q000900010012C73Q00013Q0020825Q00020020575Q0003001254000200044Q006A3Q00020002000637012Q000D000100010004F53Q000D00012Q00672Q016Q0070000100023Q00208200013Q00060012682Q0100053Q00122Q000100076Q00010001000100122Q000100086Q0001000100014Q000100016Q000100028Q00017Q000B3Q0003123Q006973506F73496E426C6F636B65645A6F6E6503063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403063Q00434672616D652Q033Q006E657703163Q00412Q73656D626C794C696E65617256656C6F6369747903073Q00566563746F723303043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747901203Q0012C7000100014Q004100026Q00332Q01000200020006202Q01000600013Q0004F53Q000600012Q005B3Q00013Q0012C7000100023Q0020820001000100030006202Q01000F00013Q0004F53Q000F00010012C7000100023Q002082000100010003002057000100010004001254000300054Q006A0001000300020006202Q01001300013Q0004F53Q00130001000637012Q0014000100010004F53Q001400012Q005B3Q00013Q0012C7000200063Q0020A60002000200074Q00038Q00020002000200102Q00010006000200122Q000200093Q00202Q00020002000A00102Q00010008000200122Q000200093Q00202Q00020002000A00102Q0001000B00026Q00017Q000A3Q0003043Q007469636B03123Q0073686F756C644661726D436F6E74696E756503043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F0002293Q0012C7000200014Q005E0002000100022Q009E000200023Q0012C7000300014Q005E00030001000200060E0103001F000100020004F53Q001F00010006202Q01001000013Q0004F53Q001000010012C7000300024Q0041000400014Q003301030002000200063701030010000100010004F53Q001000012Q006701036Q0070000300023Q0012C7000300033Q0020A900030003000400122Q000400053Q00202Q00040004000600122Q000500073Q00122Q000600053Q00202Q00060006000800122Q000700093Q00122Q000800016Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q000300010026A1000100260001000A0004F53Q002600010012C7000300024Q0041000400014Q00330103000200020004F53Q002700012Q005800036Q0067010300014Q0070000300024Q005B3Q00017Q000A3Q00030F3Q006D616E75616C53652Q6C546F6B656E03043Q007469636B030E3Q0073652Q6C496E50726F6772652Q7303043Q007461736B03043Q007761697403043Q006D6174682Q033Q006D6178027B14AE47E17A843F2Q033Q006D696E029A5Q99B93F01283Q0012C7000100013Q0012C7000200024Q005E0002000100022Q009E000200023Q0012C7000300024Q005E00030001000200060E0103001F000100020004F53Q001F00010012C7000300013Q00061D2Q01000E000100030004F53Q000E00010012C7000300033Q00063701030010000100010004F53Q001000012Q006701036Q0070000300023Q0012C7000300043Q0020A900030003000500122Q000400063Q00202Q00040004000700122Q000500083Q00122Q000600063Q00202Q00060006000900122Q0007000A3Q00122Q000800026Q0008000100024Q0008000200084Q000600086Q00048Q00033Q000100044Q000400010012C7000300013Q00061D2Q010024000100030004F53Q002400010012C7000300033Q0004F53Q002600012Q005800036Q0067010300014Q0070000300024Q005B3Q00017Q000B3Q0003143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274001F3Q0012C73Q00014Q005E3Q00010002000620012Q000F00013Q0004F53Q000F000100208200013Q000300123D000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100023Q00122Q000100026Q000100023Q0012C7000100083Q0020820001000100090006202Q01001800013Q0004F53Q001800010012C7000100083Q00208200010001000900205700010001000A0012540003000B4Q006A0001000300020006202Q01001E00013Q0004F53Q001E000100208200020001000300129B000200023Q0012C7000200024Q0070000200024Q005B3Q00017Q00123Q00030B3Q00687562506F736974696F6E03143Q0067657454656C65706F7274537061776E5061727403083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q00084003063Q0069706169727303053Q00537061776E030D3Q00537061776E4C6F636174696F6E2Q033Q0048756203093Q00776F726B7370616365030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C64576869636849734103123Q0063617074757265487562506F736974696F6E026Q00144000483Q0012C73Q00013Q000620012Q000500013Q0004F53Q000500010012C73Q00014Q00703Q00023Q0012C73Q00024Q005E3Q00010002000620012Q001400013Q0004F53Q0014000100208200013Q000300123D000200043Q00202Q00020002000500122Q000300063Q00122Q000400073Q00122Q000500066Q0002000500024Q00010001000200122Q000100013Q00122Q000100016Q000100023Q0012C7000100084Q0069010200033Q00122Q000300093Q00122Q0004000A3Q00122Q0005000B6Q0002000300012Q00052Q01000200030004F53Q003A00010012C70006000C3Q00205700060006000D2Q0041000800054Q006A0006000800020006200106003A00013Q0004F53Q003A000100205700070006000E0012540009000F4Q006A0007000900020006200107002900013Q0004F53Q0029000100063E0107002D000100060004F53Q002D00010020570007000600100012540009000F4Q0067010A00014Q006A0007000A00020006200107003A00013Q0004F53Q003A000100208200080007000300123D000900043Q00202Q00090009000500122Q000A00063Q00122Q000B00073Q00122Q000C00066Q0009000C00024Q00080008000900122Q000800013Q00122Q000800016Q000800023Q0006630001001C000100020004F53Q001C00010012C7000100114Q005E0001000100020006372Q010046000100010004F53Q004600010012C7000100043Q0020272Q010001000500122Q000200063Q00122Q000300123Q00122Q000400066Q0001000400022Q0070000100024Q005B3Q00017Q000D3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030E3Q00676574487562506F736974696F6E03073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030F3Q004855425F4E4541525F52414449555300283Q0012C73Q00013Q0020825Q0002000620012Q000900013Q0004F53Q000900010012C73Q00013Q0020825Q00020020575Q0003001254000200044Q006A3Q000200020012C7000100054Q005E000100010002000620012Q000F00013Q0004F53Q000F00010006372Q010011000100010004F53Q001100012Q006701026Q0070000200023Q0012C7000200063Q0020C600020002000700202Q00033Q000800202Q00030003000900202Q00040001000A00202Q00053Q000800202Q00050005000B4Q00020005000200122Q000300063Q00202Q00030003000700202Q00040001000900202Q00050001000A00202Q00060001000B4Q0003000600024Q00040002000300202Q00040004000C00122Q0005000D3Q00062Q00040002000100050004F53Q002500012Q005800046Q0067010400014Q0070000400024Q005B3Q00017Q000A3Q0003093Q0069734E65617248756203143Q0067657454656C65706F7274537061776E50617274030B3Q00687562506F736974696F6E03083Q00506F736974696F6E03073Q00566563746F72332Q033Q006E6577028Q00026Q000840030D3Q0074656C65706F7274487270546F030E3Q00676574487562506F736974696F6E001B3Q0012C73Q00014Q005E3Q00010002000620012Q000500013Q0004F53Q000500012Q005B3Q00013Q0012C73Q00024Q005E3Q00010002000620012Q001600013Q0004F53Q0016000100208200013Q0004001225010200053Q00202Q00020002000600122Q000300073Q00122Q000400083Q00122Q000500076Q0002000500024Q00010001000200122Q000100033Q00122Q000100093Q00122Q000200036Q0001000200016Q00013Q0012C7000100093Q0012C70002000A4Q0022010200014Q00FD00013Q00012Q005B3Q00017Q000E4Q0003093Q006661726D50686173652Q033Q0068756203103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q0063752Q72656E7454617267657450617274030D3Q0074656C65706F7274546F487562030E3Q0048756257616974456E61626C6564030C3Q004855425F574149545F4D494E03043Q006D61746803063Q0072616E646F6D030C3Q004855425F574149545F4D415803113Q00696E74652Q7275707469626C655761697402253Q0026CA00010003000100010004F53Q000300012Q00672Q0100013Q001254000200033Q001298000200023Q00122Q000200046Q00020001000100122Q000200056Q00020001000100122Q000200066Q0002000100014Q000200023Q00122Q000200073Q00062Q0001001100013Q0004F53Q001100010012C7000200084Q005A0002000100010012C7000200093Q00063701020016000100010004F53Q001600012Q0067010200014Q0070000200023Q0012C70002000A3Q0012830003000B3Q00202Q00030003000C4Q00030001000200122Q0004000D3Q00122Q0005000A6Q0004000400054Q0003000300044Q00020002000300122Q0003000E6Q000400026Q00058Q000300056Q00039Q0000017Q00033Q00030B3Q00687562526573745761697403093Q006661726D506861736503043Q0069646C65010C3Q0012C7000100014Q004100026Q00332Q01000200020006372Q010007000100010004F53Q000700012Q00672Q016Q0070000100023Q001254000100033Q00129B000100024Q00672Q0100014Q0070000100024Q005B3Q00017Q00023Q0003073Q00557365464B6579030B3Q006175746F4641637469766500063Q0012C73Q00013Q000637012Q0004000100010004F53Q000400010012C73Q00024Q00703Q00024Q005B3Q00017Q00033Q00030C3Q0073686F756C645072652Q734603133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C000F3Q0012C73Q00014Q005E3Q00010002000637012Q0005000100010004F53Q000500012Q005B3Q00013Q0012C73Q00023Q000620012Q000B00013Q0004F53Q000B00010012C73Q00033Q00020B00016Q00D73Q000200010012C73Q00033Q00020B000100014Q00D73Q000200012Q005B3Q00013Q00023Q00093Q0003133Q005669727475616C496E7075744D616E61676572030C3Q0053656E644B65794576656E7403043Q00456E756D03073Q004B6579436F646503013Q004603043Q0067616D6503043Q007461736B03043Q007761697402B81E85EB51B89E3F00173Q00120A3Q00013Q00206Q00024Q000200013Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q0005000100124Q00073Q0020825Q0008001254000100094Q00D73Q00020001001217012Q00013Q00206Q00024Q00025Q00122Q000300033Q00202Q00030003000400202Q0003000300054Q00045Q00122Q000500068Q000500016Q00017Q00023Q0003063Q006B657974617003043Q00564B5F4600043Q0012C73Q00013Q0012C7000100024Q00D73Q000200012Q005B3Q00017Q000A3Q00028Q0003093Q006D6F75736548656C6403043Q006D6174682Q033Q00616273030A3Q00686F6C644D6F75736558027Q0040030A3Q00686F6C644D6F7573655903103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C022D3Q00063E0102000300013Q0004F53Q00030001001254000200013Q0006372Q010006000100010004F53Q00060001001254000100014Q00413Q00023Q0012C7000200023Q0006200102001900013Q0004F53Q001900010012C7000200033Q00203B01020002000400122Q000300056Q000300036Q00020002000200262Q00020019000100060004F53Q001900010012C7000200033Q00203B01020002000400122Q000300076Q0003000300014Q00020002000200262Q00020019000100060004F53Q001900012Q005B3Q00013Q0012C7000200084Q005A0002000100010012C7000200093Q0006200102002400013Q0004F53Q002400010012C70002000A3Q0006D800033Q000100022Q00418Q00413Q00014Q00D70002000200010004F53Q002700010012C70002000A3Q00020B000300014Q00D70002000200012Q0067010200013Q00123F010200026Q00025Q00122Q000100073Q00122Q000200058Q00013Q00023Q00043Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D65000A3Q00126B012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q000700016Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F757365317072652Q7303083Q0066756E6374696F6E00083Q0012C73Q00013Q0012C7000100024Q0033012Q000200020026CA3Q0007000100030004F53Q000700010012C73Q00024Q005A3Q000100012Q005B3Q00017Q00033Q0003103Q0072656C656173654D6F757365486F6C6403133Q005669727475616C496E7075744D616E6167657203053Q007063612Q6C02133Q0012C7000200014Q005A0002000100010012C7000200023Q0006200102000F00013Q0004F53Q000F0001000620012Q000F00013Q0004F53Q000F00010006202Q01000F00013Q0004F53Q000F00010012C7000200033Q0006D800033Q000100022Q00418Q00413Q00014Q00D70002000200010004F53Q001200010012C7000200033Q00020B000300014Q00D70002000200012Q005B3Q00013Q00023Q00073Q0003133Q005669727475616C496E7075744D616E6167657203143Q0053656E644D6F75736542752Q746F6E4576656E74028Q0003043Q0067616D6503043Q007461736B03043Q0077616974029A5Q99A93F00173Q0012693Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q000500013Q00122Q000600043Q00122Q000700038Q0007000100124Q00053Q0020825Q0006001254000100074Q00D73Q0002000100126B012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400036Q00055Q00122Q000600043Q00122Q000700038Q000700016Q00017Q00033Q0003063Q00747970656F66030B3Q006D6F75736531636C69636B03083Q0066756E6374696F6E00083Q0012C73Q00013Q0012C7000100024Q0033012Q000200020026CA3Q0007000100030004F53Q000700010012C73Q00024Q005A3Q000100012Q005B3Q00017Q00073Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D65726103143Q00576F726C64546F56696577706F7274506F696E74030A3Q0047756953657276696365030B3Q00476574477569496E73657403013Q005803013Q005901163Q000637012Q0004000100010004F53Q000400012Q0021000100014Q0070000100023Q0012C7000100013Q0020820001000100020006372Q01000A000100010004F53Q000A00012Q0021000200024Q0070000200023Q0020570002000100032Q007500048Q00020004000200122Q000300043Q00202Q0003000300054Q00030002000200202Q00040002000600202Q00050002000700202Q0006000300074Q0005000500064Q000400034Q005B3Q00017Q00083Q0003093Q00776F726B7370616365030D3Q0043752Q72656E7443616D657261030A3Q0047756953657276696365030B3Q00476574477569496E736574030C3Q0056696577706F727453697A6503013Q0058026Q00E03F03013Q005900123Q0012C73Q00013Q0020825Q0002000637012Q0006000100010004F53Q000600012Q0021000100014Q0070000100023Q0012C7000100033Q0020300001000100044Q00010002000200202Q00023Q000500202Q00030002000600202Q00030003000700202Q00040002000800202Q00040004000700202Q0005000100084Q0004000400054Q000300038Q00017Q00043Q002Q033Q0049734103083Q00426173655061727403083Q00506F736974696F6E03163Q0046696E6446697273744368696C64576869636849734101143Q000637012Q0004000100010004F53Q000400012Q0021000100014Q0070000100023Q00205700013Q0001001254000300024Q006A0001000300020006202Q01000B00013Q0004F53Q000B000100208200013Q00032Q0070000100023Q00205700013Q0004001254000300024Q0067010400014Q006A0001000400020006202Q01001300013Q0004F53Q001300010020820002000100032Q0070000200024Q005B3Q00017Q00063Q00030F3Q0067657450617274506F736974696F6E030B3Q0041696D417454617267657403113Q0063752Q72656E745461726765745061727403063Q00506172656E74030C3Q006765745363722Q656E506F7303143Q0067657446612Q6C6261636B5363722Q656E506F73011F3Q0012342Q0100016Q00028Q00010002000200122Q000200023Q00062Q0002001200013Q0004F53Q001200010012C7000200033Q0006200102001200013Q0004F53Q001200010012C7000200033Q0020820002000200040006200102001200013Q0004F53Q001200010012C7000200013Q0012C7000300034Q003301020002000200063E2Q010012000100020004F53Q001200010012C7000200054Q0041000300014Q00050102000200030006370102001B000100010004F53Q001B00010012C7000400064Q00880004000100052Q0041000300054Q0041000200044Q0041000400024Q0041000500034Q009C000400034Q005B3Q00017Q00073Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403043Q004465616403053Q0056616C75652Q0103063Q004865616C7468028Q00011E3Q00205700013Q0001001254000300024Q006A0001000300020006372Q010007000100010004F53Q000700012Q006701026Q0070000200023Q002057000200010001001254000400034Q006A0002000400020006200102001100013Q0004F53Q001100010020820003000200040026CA00030011000100050004F53Q001100012Q006701036Q0070000300023Q002057000300010001001254000500064Q006A0003000500020006200103001B00013Q0004F53Q001B000100208200040003000400262E0104001B000100070004F53Q001B00012Q006701046Q0070000400024Q0067010400014Q0070000400024Q005B3Q00017Q00043Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403063Q004865616C746803053Q0056616C7565010F3Q00065E2Q01000500013Q0004F53Q0005000100205700013Q0001001254000300024Q006A00010003000200065E0102000A000100010004F53Q000A0001002057000200010001001254000400034Q006A0002000400020006200102000E00013Q0004F53Q000E00010020820003000200042Q0070000300024Q005B3Q00017Q00043Q00030B3Q006175746F46416374697665030F3Q00737475636B4C6173744865616C7468030A3Q00737475636B53696E6365029Q00074Q00B97Q00124Q00019Q003Q00124Q00023Q00124Q00043Q00124Q00038Q00017Q00083Q0003073Q00557365464B6579030B3Q006175746F46416374697665030D3Q006765744E6F64654865616C746803043Q007469636B030F3Q00737475636B4C6173744865616C746800030A3Q00737475636B53696E6365030F3Q00535455434B5F465F5345434F4E445301213Q0012C7000100013Q0006202Q01000600013Q0004F53Q000600012Q00672Q015Q00129B000100024Q005B3Q00013Q0012C7000100034Q004100026Q00332Q01000200020006372Q01000C000100010004F53Q000C00012Q005B3Q00013Q0012C7000200044Q005E0002000100020012C7000300053Q0026A100030014000100060004F53Q001400010012C7000300053Q00060E2Q010019000100030004F53Q0019000100129B000100053Q00129B000200074Q006701035Q00129B000300023Q0004F53Q002000010012C7000300075Q000103000200030012C7000400083Q00061300040020000100030004F53Q002000012Q0067010300013Q00129B000300024Q005B3Q00017Q00083Q0003063Q00697061697273030B3Q004765744368696C6472656E03043Q004E616D6503063Q00486974626F782Q033Q0049734103083Q00426173655061727403053Q007461626C6503063Q00696E7365727401174Q009700015Q00122Q000200013Q00202Q00033Q00024Q000300046Q00023Q000400044Q001300010020820007000600030026CA00070013000100040004F53Q00130001002057000700060005001254000900064Q006A0007000900020006200107001300013Q0004F53Q001300010012C7000700073Q0020820007000700082Q0041000800014Q0041000900064Q005F00070009000100066300020006000100020004F53Q000600012Q0070000100024Q005B3Q00017Q00033Q002Q033Q0049734103083Q00426173655061727403163Q0046696E6446697273744368696C645768696368497341010C3Q00205700013Q0001001254000300024Q006A0001000300020006202Q01000600013Q0004F53Q000600012Q00703Q00023Q00205700013Q0003001244000300026Q000400016Q000100046Q00019Q0000017Q00063Q00030E3Q0046696E6446697273744368696C64030D3Q0042692Q6C626F6172645061727403083Q00506F736974696F6E030B3Q00676574486974626F786573028Q00026Q00F03F01113Q00205700013Q0001001254000300024Q006A0001000300020006202Q01000700013Q0004F53Q000700010020820002000100032Q0070000200023Q0012C7000200044Q004100036Q00330102000200022Q0006010300023Q000E0500050010000100030004F53Q001000010020820003000200060020820003000300032Q0070000300024Q005B3Q00017Q00073Q0003053Q007063612Q6C028Q00030F3Q00707573684661726D5761726E696E67030A3Q006E6F5F7461726765747303253Q00D09DD0B5D18220D186D0B5D0BBD0B5D0B920D0B4D0BBD18F20D0B4D0BED0B1D18BD187D0B803103Q00636C6561724661726D5761726E696E6703073Q006E6F5F6D6F6465001D4Q00F18Q00F100015Q0012C7000200013Q0006D800033Q000100022Q00418Q00413Q00014Q00D70002000200012Q000601025Q000E050002000C000100020004F53Q000C000100063E0102000D00013Q0004F53Q000D00012Q0041000200014Q0006010300023Q0026CA00030015000100020004F53Q001500010012C7000300033Q001254000400043Q001254000500054Q005F0003000500010004F53Q001B00010012C7000300063Q0012D4000400046Q00030002000100122Q000300063Q00122Q000400076Q0003000200012Q0070000200024Q005B3Q00013Q00013Q00163Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E73030F3Q00707573684661726D5761726E696E67030F3Q006E6F5F696E746572616374696F6E7303203Q00D09DD0B5D18220496E746572616374696F6E7320D0B220776F726B737061636503103Q00636C6561724661726D5761726E696E6703053Q004E6F64657303083Q006E6F5F6E6F64657303173Q00D09DD0B5D18220D0BFD0B0D0BFD0BAD0B8204E6F64657303043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C69766503133Q0069734E6F6465496E426C6F636B65645A6F6E6503053Q007461626C6503063Q00696E7365727403043Q006E6F646503043Q006B696E6403043Q0074722Q6503093Q005265736F757263657303053Q0073746F6E6500563Q0012803Q00013Q00206Q000200122Q000200038Q0002000200064Q000B000100010004F53Q000B00010012C7000100043Q001254000200053Q001254000300064Q005F0001000300012Q005B3Q00013Q0012C7000100073Q001253000200056Q00010002000100202Q00013Q000200122Q000300086Q00010003000200062Q00010018000100010004F53Q001800010012C7000200043Q001254000300093Q0012540004000A4Q005F0002000400012Q005B3Q00013Q0012C7000200073Q0012C4000300096Q00020002000100202Q00020001000200122Q0004000B6Q00020004000200062Q0002003800013Q0004F53Q003800010012C70003000C3Q00205700040002000D2Q0065010400054Q004900033Q00050004F53Q003600010012C70008000E4Q0041000900074Q00330108000200020006200108003600013Q0004F53Q003600010012C70008000F4Q0041000900074Q003301080002000200063701080036000100010004F53Q003600010012C7000800103Q00205D0108000800114Q00098Q000A3Q000200102Q000A0012000700302Q000A001300144Q0008000A000100066300030025000100020004F53Q00250001002057000300010002001254000500154Q006A0003000500020006200103005500013Q0004F53Q005500010012C70004000C3Q00205700050003000D2Q0065010500064Q004900043Q00060004F53Q005300010012C70009000E4Q0041000A00084Q00330109000200020006200109005300013Q0004F53Q005300010012C70009000F4Q0041000A00084Q003301090002000200063701090053000100010004F53Q005300010012C7000900103Q00205D0109000900114Q000A00016Q000B3Q000200102Q000B0012000800302Q000B001300164Q0009000B000100066300040042000100020004F53Q004200012Q005B3Q00017Q00043Q00028Q0003053Q007063612Q6C030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E74000D3Q0012543Q00013Q001254000100013Q0012C7000200023Q0006D800033Q000100022Q00418Q00413Q00014Q008500020002000100124Q00033Q00122Q000100046Q00028Q000300016Q000200038Q00013Q00013Q000A3Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C64030C3Q00496E746572616374696F6E7303053Q004E6F64657303043Q00462Q6F6403063Q00697061697273030B3Q004765744368696C6472656E030B3Q0069734E6F6465416C697665026Q00F03F03093Q005265736F757263657300363Q0012803Q00013Q00206Q000200122Q000200038Q0002000200064Q0007000100010004F53Q000700012Q005B3Q00013Q00205700013Q0002001254000300044Q006A0001000300020006372Q01000D000100010004F53Q000D00012Q005B3Q00013Q002057000200010002001254000400054Q006A0002000400020006200102002100013Q0004F53Q002100010012C7000300063Q0020570004000200072Q0065010400054Q004900033Q00050004F53Q001F00010012C7000800084Q0041000900074Q00330108000200020006200108001F00013Q0004F53Q001F00012Q009D00085Q0020A50008000800092Q004801085Q00066300030017000100020004F53Q001700010020570003000100020012540005000A4Q006A0003000500020006200103003500013Q0004F53Q003500010012C7000400063Q0020570005000300072Q0065010500064Q004900043Q00060004F53Q003300010012C7000900084Q0041000A00084Q00330109000200020006200109003300013Q0004F53Q003300012Q009D000900013Q0020A50009000900092Q0048010900013Q0006630004002B000100020004F53Q002B00012Q005B3Q00017Q000C3Q00028Q00030E3Q00676574487562506F736974696F6E03063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403083Q00506F736974696F6E026Q00F03F03063Q00697061697273030D3Q006765744E6F646543656E74657203043Q006E6F646503093Q004D61676E697475646501324Q00062Q015Q0026CA00010005000100010004F53Q000500012Q0021000100014Q0070000100023Q0012C7000100024Q005E0001000100020012C7000200033Q0020820002000200040006200102001000013Q0004F53Q001000010012C7000200033Q002082000200020004002057000200020005001254000400064Q006A0002000400020006200102001500013Q0004F53Q001500010006372Q010015000100010004F53Q001500010020820001000200070006372Q010019000100010004F53Q0019000100208200033Q00082Q0070000300024Q0021000300043Q0012C7000500094Q004100066Q00050105000200070004F53Q002B00010012C7000A000A3Q002082000B0009000B2Q0033010A00020002000620010A002B00013Q0004F53Q002B00013Q00010B000A0001002082000B000B000C0006200104002900013Q0004F53Q0029000100060E010B002B000100040004F53Q002B00012Q0041000300094Q00410004000B3Q0006630005001E000100020004F53Q001E000100063E01050030000100030004F53Q0030000100208200053Q00082Q0070000500024Q005B3Q00017Q00043Q00030C3Q00706174726F6C506F696E747303053Q007063612Q6C030B3Q00706174726F6C496E646578026Q00F03F00084Q00F17Q00129B3Q00013Q0012C73Q00023Q00020B00016Q00D73Q000200010012543Q00043Q00129B3Q00034Q005B3Q00013Q00013Q00073Q0003063Q00697061697273030F3Q0067657456616C696454617267657473030D3Q006765744E6F646543656E74657203043Q006E6F646503053Q007461626C6503063Q00696E73657274030C3Q00706174726F6C506F696E747300123Q0012EB3Q00013Q00122Q000100026Q000100019Q00000200044Q000F00010012C7000500033Q0020820006000400042Q00330105000200020006200105000F00013Q0004F53Q000F00010012C7000600053Q0020820006000600060012C7000700074Q0041000800054Q005F0006000800010006633Q0005000100020004F53Q000500012Q005B3Q00017Q001A3Q0003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030C3Q00706174726F6C506F696E7473028Q00030B3Q00706174726F6C496E64657803073Q00566563746F72332Q033Q006E657703183Q0067657454656C65706F7274486569676874466F724B696E6403103Q006163746976655461726765744B696E64026Q00F03F030B3Q00736561726368416E676C65026Q66D63F030C3Q00736561726368526164697573026Q007940026Q005440026Q002E4003083Q00506F736974696F6E03043Q006D6174682Q033Q00636F732Q033Q0073696E03063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747900573Q0012C73Q00013Q0020825Q0002000620012Q000900013Q0004F53Q000900010012C73Q00013Q0020825Q00020020575Q0003001254000200044Q006A3Q00020002000637012Q000C000100010004F53Q000C00012Q005B3Q00014Q0021000100013Q0012C7000200054Q0006010200023Q000E0500060029000100020004F53Q002900010012C7000200053Q0012C7000300074Q002C0002000200030006200102001F00013Q0004F53Q001F00010012C7000300083Q002Q2000030003000900122Q000400063Q00122Q0005000A3Q00122Q0006000B6Q00050002000200122Q000600066Q0003000600024Q0001000200030012C7000300073Q0020ED00030003000C00122Q000300073Q00122Q000300073Q00122Q000400056Q000400043Q00062Q00040029000100030004F53Q002900010012540003000C3Q00129B000300073Q0006372Q01004B000100010004F53Q004B00010012C70002000D3Q0020A500020002000E00129B0002000D3Q0012C70002000F3Q000E0500100034000100020004F53Q00340001001254000200113Q00129B0002000F3Q0004F53Q003700010012C70002000F3Q0020A500020002001200129B0002000F3Q00208200023Q0013001243000300083Q00202Q00030003000900122Q000400143Q00202Q00040004001500122Q0005000D6Q00040002000200122Q0005000F6Q00040004000500122Q0005000A3Q00122Q0006000B6Q00050002000200122Q000600143Q00202Q00060006001600122Q0007000D6Q00060002000200122Q0007000F6Q0006000600074Q0003000600024Q0001000200030012C7000200173Q0020A60002000200094Q000300016Q00020002000200104Q0017000200122Q000200083Q00202Q00020002001900104Q0018000200122Q000200083Q00202Q00020002001900104Q001A00026Q00017Q00063Q002Q033Q0049734103053Q004D6F64656C03063Q0069706169727303103Q0044524F505F4D4F44454C5F48494E545303043Q004E616D6503043Q0066696E6401183Q00205700013Q0001001254000300024Q006A0001000300020006372Q010007000100010004F53Q000700012Q00672Q016Q0070000100023Q0012C7000100033Q0012C7000200044Q00052Q01000200030004F53Q0013000100208200063Q00050020570006000600062Q0041000800054Q006A0006000800020006200106001300013Q0004F53Q001300012Q0067010600014Q0070000600023Q0006630001000B000100020004F53Q000B00012Q00672Q016Q0070000100024Q005B3Q00017Q00093Q0003103Q006163746976655461726765744B696E6403043Q004E616D6503043Q0066696E64030F3Q00436F2Q7065725265736F7572636573030D3Q004C6561665265736F757263657303053Q0073746F6E6503093Q00462Q6F644D6F64656C030D3Q00572Q6F645265736F757263657303043Q0074722Q6501203Q000637012Q0004000100010004F53Q000400010012C7000100014Q0070000100023Q00208200013Q0002002057000200010003001254000400044Q006A0002000400020006370102000F000100010004F53Q000F0001002057000200010003001254000400054Q006A0002000400020006200102001100013Q0004F53Q00110001001254000200064Q0070000200023Q002057000200010003001254000400074Q006A0002000400020006370102001B000100010004F53Q001B0001002057000200010003001254000400084Q006A0002000400020006200102001D00013Q0004F53Q001D0001001254000200094Q0070000200023Q0012C7000200014Q0070000200024Q005B3Q00017Q00023Q00030C3Q0069676E6F72656444726F707303063Q00506172656E7401133Q0012C7000100014Q002C000100013Q0006202Q01000600013Q0004F53Q000600012Q00672Q0100014Q0070000100023Q00208200013Q00020006202Q01001000013Q0004F53Q001000010012C7000100013Q00208200023Q00022Q002C0001000100020006202Q01001000013Q0004F53Q001000012Q00672Q0100014Q0070000100024Q00672Q016Q0070000100024Q005B3Q00017Q000B3Q00030C3Q0069676E6F72656444726F70732Q0103103Q006163746976655461726765744B696E6403063Q00506172656E742Q033Q0049734103053Q004D6F64656C03143Q0067657444726F704B696E6446726F6D4D6F64656C03053Q0073746F6E6503113Q0073652Q73696F6E53746F6E6544726F7073026Q00F03F03103Q0073652Q73696F6E54722Q6544726F7073011D3Q0012BD000100013Q00202Q00013Q000200122Q000100033Q00202Q00023Q000400062Q0002001300013Q0004F53Q0013000100208200023Q0004002057000200020005001254000400064Q006A0002000400020006200102001300013Q0004F53Q001300010012C7000200073Q00209000033Q00044Q0002000200024Q000100023Q00122Q000200013Q00202Q00033Q000400202Q0002000300020026CA00010019000100080004F53Q001900010012C7000200093Q0020A500020002000A00129B000200093Q0004F53Q001C00010012C70002000B3Q0020A500020002000A00129B0002000B4Q005B3Q00017Q00063Q0003063Q00506172656E74030D3Q00697344726F7049676E6F72656403123Q006973506F73496E426C6F636B65645A6F6E6503083Q00506F736974696F6E03013Q0059026Q00244002223Q000620012Q000500013Q0004F53Q0005000100208200023Q000100063701020007000100010004F53Q000700012Q006701026Q0070000200023Q0012C7000200024Q004100036Q00330102000200020006200102000E00013Q0004F53Q000E00012Q006701026Q0070000200023Q0012C7000200033Q00208200033Q00042Q00330102000200020006200102001500013Q0004F53Q001500012Q006701026Q0070000200023Q0006202Q01001F00013Q0004F53Q001F000100208200023Q00040020820002000200050020820003000100053Q00010200020003000E050006001F000100020004F53Q001F00012Q006701026Q0070000200024Q0067010200014Q0070000200024Q005B3Q00017Q00183Q0003093Q00776F726B7370616365030E3Q0046696E6446697273744368696C6403063Q0043616D657261030F3Q00707573684661726D5761726E696E6703093Q006E6F5F63616D657261032A3Q00D09DD0B5D1822043616D65726120E2809420D0BBD183D18220D0BDD0B520D0BDD0B0D0B9D0B4D0B5D0BD03103Q00636C6561724661726D5761726E696E6703063Q00697061697273030B3Q004765744368696C6472656E03133Q0069735265736F7572636544726F704D6F64656C03063Q00506172656E74030E3Q00676574436F2Q6C6563745061727403123Q00697356616C6964436F2Q6C65637444726F7003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465030E3Q00434F2Q4C4543545F52414449555303053Q007461626C6503063Q00696E7365727403043Q00736F727401464Q00F100015Q000637012Q0004000100010004F53Q000400012Q0070000100023Q0012C7000200013Q002057000200020002001254000400034Q006A0002000400020006370102000F000100010004F53Q000F00010012C7000300043Q001254000400053Q001254000500064Q005F0003000500012Q0070000100023Q0012C7000300073Q00125C010400056Q00030002000100122Q000300083Q00202Q0004000200094Q000400056Q00033Q000500044Q003C00010012C70008000A4Q0041000900074Q00330108000200020006200108003C00013Q0004F53Q003C000100208200080007000B0006200108003C00013Q0004F53Q003C00010012C70008000C4Q0041000900074Q00330108000200020006200108003C00013Q0004F53Q003C00010012C70009000D4Q0041000A00084Q0041000B6Q006A0009000B00020006200109003C00013Q0004F53Q003C00010012C70009000E3Q00201700090009000F00202Q000A0008001000202Q000A000A001100202Q000B3Q001200202Q000C0008001000202Q000C000C00134Q0009000C00024Q000900093Q00202Q00090009001400122Q000A00153Q00062Q0009003C0001000A0004F53Q003C00010012C7000A00163Q002082000A000A00172Q0041000B00014Q0041000C00084Q005F000A000C000100066300030017000100020004F53Q001700010012C7000300163Q0020820003000300182Q0041000400013Q0006D800053Q000100012Q00418Q005F0003000500012Q0070000100024Q005B3Q00013Q00013Q00073Q0003073Q00566563746F72332Q033Q006E657703083Q00506F736974696F6E03013Q005803013Q005903013Q005A03093Q004D61676E6974756465021E3Q001232000200013Q00202Q00020002000200202Q00033Q000300202Q0003000300044Q00045Q00202Q00040004000500202Q00053Q000300202Q0005000500064Q0002000500024Q00038Q00020002000300202Q00020002000700122Q000300013Q00202Q00030003000200202Q00040001000300202Q0004000400044Q00055Q00202Q00050005000500202Q00060001000300202Q0006000600064Q0003000600024Q00048Q00030003000400202Q00030003000700062Q0002001B000100030004F53Q001B00012Q005800046Q0067010400014Q0070000400024Q005B3Q00017Q00023Q00030D3Q006765744E6F646543656E74657203173Q0066696E6443616D6572615265736F7572636544726F7073010C3Q0012C7000100014Q004100026Q00332Q01000200020006372Q010007000100010004F53Q000700012Q00F100026Q0070000200023Q0012C7000200024Q0041000300014Q003E000200034Q001F01026Q005B3Q00017Q00073Q0003113Q006D61726B44726F70436F2Q6C656374656403163Q0046696E6446697273744368696C645768696368497341030F3Q0050726F78696D69747950726F6D707403063Q00506172656E7403053Q007063612Q6C030C3Q0073686F756C645072652Q734603063Q007072652Q734601223Q000637012Q0003000100010004F53Q000300012Q005B3Q00013Q0012C7000100014Q002200028Q00010002000100202Q00013Q000200122Q000300036Q000400016Q00010004000200062Q00010015000100010004F53Q0015000100208200023Q00040006200102001500013Q0004F53Q0015000100208200023Q00040020B100020002000200122Q000400036Q000500016Q0002000500024Q000100023Q0006202Q01001B00013Q0004F53Q001B00010012C7000200053Q0006D800033Q000100012Q00413Q00014Q00D70002000200010012C7000200064Q005E0002000100020006200102002100013Q0004F53Q002100010012C7000200074Q005A0002000100012Q005B3Q00013Q00013Q00013Q0003133Q006669726570726F78696D69747970726F6D707400043Q0012C73Q00014Q009D00016Q00D73Q000200012Q005B3Q00017Q00163Q0003093Q006661726D506861736503073Q00636F2Q6C656374030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E7454617267657450617274030D3Q006765744E6F646543656E746572030C3Q0069676E6F72656444726F7073026Q00F03F026Q00344003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E65617203063Q0069706169727303123Q00697356616C6964436F2Q6C65637444726F7003083Q00506F736974696F6E030D3Q0074656C65706F7274487270546F03113Q00696E74652Q7275707469626C6557616974027B14AE47E17AB43F030B3Q00636F2Q6C65637450617274029A5Q99A93F029A5Q99B93F03133Q0073746F704368617261637465724D6F74696F6E02593Q0012AB000200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200076Q00038Q0002000200024Q00035Q00122Q000300083Q00122Q000300093Q00122Q0004000A3Q00122Q000500093Q00042Q0003005400010012C70007000B4Q0041000800014Q003301070002000200063701070017000100010004F53Q001700010004F53Q005400010012C70007000C4Q004100086Q00330107000200022Q0006010800073Q0026CA0008001E000100040004F53Q001E00010004F53Q005400010012C70008000D4Q0041000900074Q000501080002000A0004F53Q004A00010012C7000D000B4Q0041000E00014Q0033010D00020002000637010D0028000100010004F53Q002800010004F53Q004A00010012C7000D000E4Q0041000E000C4Q0041000F00024Q006A000D000F0002000637010D002F000100010004F53Q002F00010004F53Q004A0001002082000D000C000F001211000E00106Q000F000D6Q000E0002000100122Q000C00063Q00122Q000E00113Q00122Q000F00126Q001000016Q000E0010000200062Q000E003B000100010004F53Q003B00010004F53Q004A00010012C7000E00104Q0046000F000D6Q000E0002000100122Q000E00136Q000F000C6Q000E0002000100122Q000E00113Q00122Q000F00146Q001000016Q000E0010000200062Q000E0048000100010004F53Q004800010004F53Q004A00012Q0021000E000E3Q00129B000E00063Q00066300080022000100020004F53Q002200010012C7000800113Q001254000900154Q0041000A00014Q006A0008000A000200063701080053000100010004F53Q005300010004F53Q0054000100046C0003001100012Q0021000300033Q00129B000300063Q0012C7000300164Q005A0003000100012Q005B3Q00017Q00053Q0003063Q007072652Q7346030F3Q0067657441696D5363722Q656E506F7303083Q00557365436C69636B03073Q00636C69636B4174030B3Q00686F6C644D6F7573654174011A3Q000637012Q0003000100010004F53Q000300012Q005B3Q00013Q0012C7000100014Q001000010001000100122Q000100026Q00028Q00010002000200062Q0001000C00013Q0004F53Q000C00010006370102000D000100010004F53Q000D00012Q005B3Q00013Q0012C7000300033Q0006200103001500013Q0004F53Q001500010012C7000300044Q0041000400014Q0041000500024Q005F0003000500010004F53Q001900010012C7000300054Q0041000400014Q0041000500024Q005F0003000500012Q005B3Q00017Q00043Q0003063Q0069706169727303163Q00412Q73656D626C794C696E65617256656C6F6369747903093Q004D61676E6974756465026Q00F83F010F3Q0012C7000100014Q004100026Q00052Q01000200030004F53Q000A0001002082000600050002002082000600060003000E050004000A000100060004F53Q000A00012Q006701066Q0070000600023Q00066300010004000100020004F53Q000400012Q00672Q0100014Q0070000100024Q005B3Q00017Q000F3Q0003093Q006661726D506861736503043Q0077616974030A3Q006F72626974416E676C65028Q0003103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403113Q00696E74652Q7275707469626C6557616974026Q00D03F03043Q007469636B026Q00084003123Q0073686F756C644661726D436F6E74696E7565030D3Q0066696E6444726F70734E656172030F3Q0064726F707341726553652Q746C6564026Q00F03F029A5Q99B93F023E3Q00128E000200023Q00122Q000200013Q00122Q000200043Q00122Q000200033Q00122Q000200056Q0002000100014Q000200023Q00122Q000200063Q00122Q000200073Q00122Q000300086Q000400016Q00020004000200062Q00020010000100010004F53Q001000012Q00F100026Q0070000200023Q0012C7000200094Q005E0002000100020020A500020002000A0012C70003000B4Q0041000400014Q00330103000200020006200103003900013Q0004F53Q003900010012C7000300094Q005E00030001000200060E01030039000100020004F53Q003900010012C70003000C4Q004100046Q00330103000200022Q0006010400033Q000E0500040029000100040004F53Q002900010012C70004000D4Q0041000500034Q00330104000200020006200104003000013Q0004F53Q003000012Q0070000300023Q0004F53Q003000010012C7000400094Q005E0004000100020020BE00050002000E00060E01050030000100040004F53Q003000012Q00F100046Q0070000400023Q0012C7000400073Q0012540005000F4Q0041000600014Q006A00040006000200063701040013000100010004F53Q001300012Q00F100046Q0070000400023Q0004F53Q001300010012C70003000C4Q004100046Q003E000300044Q001F01036Q005B3Q00017Q00023Q0003053Q0073746F6E65030D3Q006765744E6F646543656E746572030C3Q0026CA0001000A000100010004F53Q000A0001000620012Q000A00013Q0004F53Q000A00010012C7000300024Q004100046Q00330103000200020006200103000A00013Q0004F53Q000A00012Q0070000300024Q0070000200024Q005B3Q00017Q00243Q0003093Q006661726D506861736503043Q006D696E6503113Q0063752Q72656E745461726765745061727403063Q00506172656E7403063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F7450617274030F3Q0067657450617274506F736974696F6E03103Q006765744D696E65416E63686F72506F73030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403183Q0067657454656C65706F7274486569676874466F724B696E6403013Q0059030C3Q004F72626974456E61626C6564030A3Q006F72626974416E676C65030A3Q004F7262697453702Q6564026Q11913F030D3Q004F726269744469616D65746572027Q004003073Q00566563746F72332Q033Q006E657703013Q005803043Q006D6174682Q033Q00636F7303013Q005A2Q033Q0073696E030B3Q0041696D417454617267657403053Q0073746F6E6503063Q00434672616D6503163Q00412Q73656D626C794C696E65617256656C6F6369747903043Q007A65726F03173Q00412Q73656D626C79416E67756C617256656C6F6369747903083Q00557365436C69636B030F3Q0067657441696D5363722Q656E506F73030B3Q00686F6C644D6F757365417400743Q0012C73Q00013Q0026A13Q0004000100020004F53Q000400012Q005B3Q00013Q0012C73Q00033Q000620012Q000B00013Q0004F53Q000B00010012C73Q00033Q0020825Q0004000637012Q000C000100010004F53Q000C00012Q005B3Q00013Q0012C73Q00053Q0020825Q0006000620012Q001500013Q0004F53Q001500010012C73Q00053Q0020825Q00060020575Q0007001254000200084Q006A3Q00020002000637012Q0018000100010004F53Q001800012Q005B3Q00013Q0012C7000100093Q0012C7000200034Q00332Q01000200020006372Q01001E000100010004F53Q001E00012Q005B3Q00013Q0012C70002000A3Q0012890003000B3Q00122Q0004000C6Q000500016Q00020005000200122Q0003000D3Q00122Q0004000C6Q00030002000200202Q00040002000E4Q0004000400034Q000500053Q00122Q0006000F3Q00062Q0006004700013Q0004F53Q004700010012C7000600103Q0012B2000700113Q00202Q0007000700124Q00060006000700122Q000600103Q00122Q000600133Q00202Q00060006001400122Q000700153Q00202Q00070007001600202Q00080002001700122Q000900183Q00202Q00090009001900122Q000A00106Q0009000200024Q0009000900064Q0008000800094Q000900043Q00202Q000A0002001A00122Q000B00183Q00202Q000B000B001B00122Q000C00106Q000B000200024Q000B000B00064Q000A000A000B4Q0007000A00024Q000500073Q00044Q004E00010012C7000600153Q00205500060006001600202Q0007000200174Q000800043Q00202Q00090002001A4Q0006000900024Q000500063Q0012C70006001C3Q0006200106005B00013Q0004F53Q005B00010012C70006000C3Q0026A10006005B0001001D0004F53Q005B00010012C70006001E3Q00202Q0106000600164Q000700056Q000800016Q00060008000200104Q001E000600044Q006000010012C70006001E3Q0020820006000600162Q0041000700054Q00330106000200020010783Q001E00060012C7000600153Q00201400060006002000104Q001F000600122Q000600153Q00202Q00060006002000104Q0021000600122Q000600223Q00062Q00060073000100010004F53Q007300010012C7000600033Q0006200106007300013Q0004F53Q007300010012C7000600233Q0012F8000700036Q00060002000700122Q000800246Q000900066Q000A00076Q0008000A00012Q005B3Q00017Q00023Q00030C3Q007363722Q656E477569526566030E3Q00497344657363656E64616E744F66010E3Q0012C7000100013Q0006202Q01000C00013Q0004F53Q000C00010012C7000100013Q0006E93Q000B000100010004F53Q000B000100205700013Q00020012C7000300014Q006A0001000300020004F53Q000C00012Q005800016Q00672Q0100014Q0070000100024Q005B3Q00017Q00073Q0003063Q00737472696E6703053Q006C6F77657203043Q004E616D6503063Q00697061697273030B3Q0054524144455F48494E545303043Q0066696E64026Q00F03F01183Q001259000100013Q00202Q00010001000200202Q00023Q00034Q00010002000200122Q000200043Q00122Q000300056Q00020002000400044Q001300010012C7000700013Q00202A0007000700064Q000800016Q000900063Q00122Q000A00076Q000B00016Q0007000B000200062Q0007001300013Q0004F53Q001300012Q0067010700014Q0070000700023Q00066300020008000100020004F53Q000800012Q006701026Q0070000200024Q005B3Q00017Q00083Q0003083Q0069734F75724775692Q033Q0049734103093Q005363722Q656E47756903073Q00456E61626C6564010003093Q004775694F626A65637403073Q0056697369626C6503063Q0041637469766501153Q0012C7000100014Q004100026Q00332Q01000200020006202Q01000600013Q0004F53Q000600012Q005B3Q00013Q00205700013Q0002001254000300034Q006A0001000300020006202Q01000D00013Q0004F53Q000D00010030F93Q000400050004F53Q0014000100205700013Q0002001254000300064Q006A0001000300020006202Q01001400013Q0004F53Q001400010030F93Q000700050030F93Q000800052Q005B3Q00017Q00053Q00030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B655472616465030F3Q006869646554726164654F626A65637403063Q00697061697273030E3Q0047657444657363656E64616E7473011E3Q0012C7000100013Q0006202Q01000500013Q0004F53Q00050001000637012Q0006000100010004F53Q000600012Q005B3Q00013Q0012C7000100024Q004100026Q00332Q01000200020006202Q01000E00013Q0004F53Q000E00010012C7000100034Q004100026Q00D70001000200010012C7000100043Q00205700023Q00052Q0065010200034Q004900013Q00030004F53Q001B00010012C7000600024Q0041000700054Q00330106000200020006200106001B00013Q0004F53Q001B00010012C7000600034Q0041000700054Q00D700060002000100066300010013000100020004F53Q001300012Q005B3Q00017Q000B3Q0003113Q00426C6F636B5569447572696E674661726D03063Q0069706169727303093Q00706C61796572477569030B3Q004765744368696C6472656E2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F757247756903073Q00456E61626C6564030A3Q0068692Q64656E477569733Q012Q001D3Q0012C73Q00013Q000637012Q0004000100010004F53Q000400012Q005B3Q00013Q0012C73Q00023Q0012322Q0100033Q00202Q0001000100044Q000100029Q00000200044Q001A0001002057000500040005001254000700064Q006A0005000700020006200105001A00013Q0004F53Q001A00010012C7000500074Q0041000600044Q00330105000200020006370105001A000100010004F53Q001A00010020820005000400080006200105001A00013Q0004F53Q001A00010012C7000500093Q0020BB00050004000A0030F900040008000B0006633Q000A000100020004F53Q000A00012Q005B3Q00017Q00023Q0003053Q0070616972730001083Q0012C7000100014Q004100026Q00052Q01000200030004F53Q000500010020BB3Q0004000200066300010004000100010004F53Q000400012Q005B3Q00017Q000A3Q0003053Q00706169727303133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q007063612Q6C030A3Q00636C6561725461626C65030A3Q0068692Q64656E4775697303063Q00506172656E742Q0103043Q006E65787403043Q007461736B03053Q006465666572002B3Q0012C73Q00013Q0012C7000100024Q0005012Q000200020004F53Q000B00010006200104000A00013Q0004F53Q000A00010012C7000500033Q0006D800063Q000100012Q00413Q00044Q00D70005000200012Q001C01035Q0006633Q0004000100020004F53Q000400010012C73Q00043Q00123D2Q0100028Q000200019Q0000122Q000100013Q00122Q000200056Q00010002000300044Q001B00010020820006000400060006200106001B00013Q0004F53Q001B00010006200105001B00013Q0004F53Q001B00010020BB3Q0004000700066300010015000100020004F53Q001500010012C7000100043Q00122C010200056Q00010002000100122Q000100086Q00028Q00010002000200062Q0001002A00013Q0004F53Q002A00010012C7000100093Q00208200010001000A0006D800020001000100012Q00418Q00D70001000200012Q005B3Q00013Q00023Q00013Q00030A3Q00446973636F2Q6E65637400044Q009D7Q0020575Q00012Q00D73Q000200012Q005B3Q00017Q00043Q0003053Q00706169727303063Q00506172656E7403073Q00456E61626C65642Q01000B3Q0012C73Q00014Q009D00016Q0005012Q000200020004F53Q000800010020820004000300020006200104000800013Q0004F53Q000800010030F90003000300040006633Q0004000100010004F53Q000400012Q005B3Q00017Q000A3Q00030C3Q0073746F70536166654D6F6465030D3Q00686964654F7468657247756973030A3Q007363616E54726164657303093Q00706C6179657247756903133Q00736166654D6F6465436F2Q6E656374696F6E7303053Q006368696C64030A3Q004368696C64412Q64656403073Q00436F2Q6E65637403043Q0064657363030F3Q0044657363656E64616E74412Q64656400163Q001256012Q00018Q0001000100124Q00028Q0001000100124Q00033Q00122Q000100048Q0002000100124Q00053Q00122Q000100043Q00202Q00010001000700202Q00010001000800020B00036Q003800010003000200104Q0006000100124Q00053Q00122Q000100043Q00202Q00010001000A00202Q00010001000800020B000300014Q006A0001000300020010783Q000900012Q005B3Q00013Q00023Q00033Q00030B3Q004661726D456E61626C656403043Q007461736B03053Q006465666572010A3Q0012C7000100013Q0006372Q010004000100010004F53Q000400012Q005B3Q00013Q0012C7000100023Q0020820001000100030006D800023Q000100012Q00418Q00D70001000200012Q005B3Q00013Q00013Q00093Q0003113Q00426C6F636B5569447572696E674661726D2Q033Q0049734103093Q005363722Q656E47756903083Q0069734F7572477569030A3Q0068692Q64656E477569732Q0103073Q00456E61626C65640100030A3Q007363616E54726164657300173Q0012C73Q00013Q000620012Q001300013Q0004F53Q001300012Q009D7Q0020575Q0002001254000200034Q006A3Q00020002000620012Q001300013Q0004F53Q001300010012C73Q00044Q009D00016Q0033012Q00020002000637012Q0013000100010004F53Q001300010012C73Q00054Q009D00015Q0020BB3Q000100062Q009D7Q0030F93Q000700080012C73Q00094Q009D00016Q00D73Q000200012Q005B3Q00017Q00053Q00030B3Q004661726D456E61626C6564030B3Q00426C6F636B547261646573030E3Q006C2Q6F6B734C696B65547261646503043Q007461736B03053Q00646566657201123Q0012C7000100013Q0006202Q01000600013Q0004F53Q000600010012C7000100023Q0006372Q010007000100010004F53Q000700012Q005B3Q00013Q0012C7000100034Q004100026Q00332Q01000200020006202Q01001100013Q0004F53Q001100010012C7000100043Q0020820001000100050006D800023Q000100012Q00418Q00D70001000200012Q005B3Q00013Q00013Q00013Q00030F3Q006869646554726164654F626A65637400043Q0012C73Q00014Q009D00016Q00D73Q000200012Q005B3Q00017Q00043Q0003063Q00706C61796572030E3Q0046696E6446697273744368696C6403043Q004461746103093Q005265736F7572636573000D3Q0012803Q00013Q00206Q000200122Q000200038Q0002000200064Q0008000100010004F53Q000800012Q0021000100014Q0070000100023Q00205700013Q0002001254000300044Q003E000100034Q001F2Q016Q005B3Q00017Q00073Q0003123Q006765745265736F7572636573466F6C646572028Q00030E3Q0046696E6446697273744368696C642Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565011A3Q0012C7000100014Q005E0001000100020006372Q010006000100010004F53Q00060001001254000200024Q0070000200023Q0020570002000100032Q004100046Q006A0002000400020006200102001700013Q0004F53Q00170001002057000300020004001254000500054Q006A00030005000200063701030015000100010004F53Q00150001002057000300020004001254000500064Q006A0003000500020006200103001700013Q0004F53Q001700010020820003000200072Q0070000300023Q001254000300024Q0070000300024Q005B3Q00017Q00053Q00028Q0003073Q00436F636F6E757403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7400133Q0012743Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300046Q00020002000400044Q000D00010012C7000700054Q0041000800064Q003301070002000200060E012Q000D000100070004F53Q000D00012Q00413Q00074Q0041000100063Q00066300020006000100020004F53Q000600012Q004100026Q0041000300014Q009C000200034Q005B3Q00017Q00053Q00030F3Q004175746F53652Q6C456E61626C656403063Q00697061697273030A3Q0053452Q4C5F4954454D5303113Q006765745265736F75726365416D6F756E7403143Q0053652Q6C436F636F6E75745468726573686F6C6400163Q0012C73Q00013Q000637012Q0005000100010004F53Q000500012Q0067017Q00703Q00023Q0012C73Q00023Q0012C7000100034Q0005012Q000200020004F53Q001100010012C7000500044Q0041000600044Q00330105000200020012C7000600053Q00060E01060011000100050004F53Q001100012Q0067010500014Q0070000500023Q0006633Q0009000100020004F53Q000900012Q0067017Q00703Q00024Q005B3Q00017Q00073Q00030D3Q006661726D54696D65546F74616C030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q0003043Q007469636B03043Q006D61746803053Q00666C2Q6F7200123Q0012C73Q00013Q0012C7000100023Q0006202Q01000C00013Q0004F53Q000C00010012C7000100033Q000E050004000C000100010004F53Q000C00010012C7000100054Q005E0001000100020012C7000200035Q002Q01000100022Q009E5Q00010012C7000100063Q0020B00001000100074Q00028Q000100026Q00019Q0000017Q00073Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E2Q033Q0073796E03043Q00682Q7470030B3Q00482Q747053657276696365030C3Q00526571756573744173796E63013A3Q00020B00015Q0012C7000200013Q0012C7000300024Q00330102000200020026CA0002000D000100030004F53Q000D00012Q0041000200013Q0006D800030001000100012Q00418Q00330102000200020006200102000D00013Q0004F53Q000D00012Q0070000200023Q0012C7000200043Q0006200102001B00013Q0004F53Q001B00010012C7000200043Q0020820002000200020006200102001B00013Q0004F53Q001B00012Q0041000200013Q0006D800030002000100012Q00418Q00330102000200020006200102001B00013Q0004F53Q001B00012Q0070000200023Q0012C7000200053Q0006200102002900013Q0004F53Q002900010012C7000200053Q0020820002000200020006200102002900013Q0004F53Q002900012Q0041000200013Q0006D800030003000100012Q00418Q00330102000200020006200102002900013Q0004F53Q002900012Q0070000200023Q0012C7000200063Q0006200102003700013Q0004F53Q003700010012C7000200063Q0020820002000200070006200102003700013Q0004F53Q003700012Q0041000200013Q0006D800030004000100012Q00418Q00330102000200020006200102003700013Q0004F53Q003700012Q0070000200024Q0021000200024Q0070000200024Q005B3Q00013Q00053Q00013Q0003053Q007063612Q6C01093Q0012C7000100014Q004100026Q00052Q01000200020006202Q01000600013Q0004F53Q000600012Q0070000200024Q0021000300034Q0070000300024Q005B3Q00017Q00013Q0003073Q007265717565737400053Q001208012Q00016Q00019Q0000019Q008Q00017Q00023Q002Q033Q0073796E03073Q007265717565737400063Q00121B3Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00023Q0003043Q00682Q747003073Q007265717565737400063Q00121B3Q00013Q00206Q00024Q00019Q0000019Q008Q00017Q00073Q00030B3Q00482Q747053657276696365030C3Q00526571756573744173796E632Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q004865616465727303043Q00426F647900153Q0012FB3Q00013Q00206Q00024Q00023Q00044Q00035Q00202Q00030003000300102Q0002000300034Q00035Q00202Q00030003000400062Q0003000B000100010004F53Q000B0001001254000300053Q0010780002000400032Q00D100035Q00202Q00030003000600102Q0002000600034Q00035Q00202Q00030003000700102Q0002000700036Q00029Q008Q00017Q001F3Q0003043Q006773756203043Q005E25732B034Q0003043Q0025732B2403143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B9030B3Q00682Q7470526571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030A3Q00537461747573436F646503063Q0073746174757303063Q0053746174757303083Q00746F6E756D626572026Q006940025Q00C0724003143Q00D09ED182D0BFD180D0B0D0B2D0BBD0B5D0BDD0BE03053Q00482Q54502003083Q00746F737472696E6703073Q0053752Q63652Q733Q010003113Q00482Q545020D0BED188D0B8D0B1D0BAD0B003053Q007063612Q6C031D3Q00D09ED188D0B8D0B1D0BAD0B020D0BED182D0BFD180D0B0D0B2D0BAD0B82Q033Q00737562026Q00F03F026Q005840025D3Q00207B00023Q000100122Q000400023Q00122Q000500036Q00020005000200202Q00020002000100122Q000400043Q00122Q000500036Q0002000500026Q00023Q00264Q000E000100030004F53Q000E00012Q006701025Q001254000300054Q009C000200033Q0012C7000200064Q000F01033Q000400102Q000300073Q00302Q0003000800094Q00043Q000100302Q0004000B000C00102Q0003000A000400102Q0003000D00014Q00020002000200062Q0002004700013Q0004F53Q0047000100208200030002000E00063701030020000100010004F53Q0020000100208200030002000F00063701030020000100010004F53Q002000010020820003000200100006200103003800013Q0004F53Q003800010012C7000400114Q0041000500034Q00330104000200020006200104003800013Q0004F53Q003800010012C7000400114Q0041000500034Q0033010400020002000E7C00120031000100040004F53Q0031000100264601040031000100130004F53Q003100012Q0067010500013Q001254000600144Q009C000500034Q006701055Q00121E000600153Q00122Q000700166Q000800036Q0007000200024Q0006000600074Q000500033Q0020820004000200170026CA0004003E000100180004F53Q003E00012Q0067010400013Q001254000500144Q009C000400033Q0020820004000200170026CA00040044000100190004F53Q004400012Q006701045Q0012540005001A4Q009C000400034Q0067010400013Q001254000500144Q009C000400033Q0012C70003001B3Q0006D800043Q000100022Q00418Q00413Q00014Q00050103000200040006200103005100013Q0004F53Q005100012Q0067010500013Q001254000600144Q009C000500034Q006701055Q0012C7000600163Q00063E01070056000100040004F53Q005600010012540007001C4Q003301060002000200207F00060006001D00122Q0008001E3Q00122Q0009001F6Q000600096Q00059Q0000013Q00013Q00053Q00030B3Q00482Q74705365727669636503093Q00506F73744173796E6303043Q00456E756D030F3Q00482Q7470436F6E74656E7454797065030F3Q00412Q706C69636174696F6E4A736F6E000A3Q002Q12012Q00013Q00206Q00024Q00028Q000300013Q00122Q000400033Q00202Q00040004000400202Q0004000400054Q00059Q00000500016Q00017Q001F3Q00034Q0003143Q00576562682Q6F6B20D0BFD183D181D182D0BED0B903043Q006E616D65030A3Q00D098D0B3D180D0BED0BA03053Q0076616C756503063Q00706C6179657203043Q004E616D652Q033Q0020286003083Q00746F737472696E6703063Q0055736572496403023Q00602903063Q00696E6C696E65010003063Q0069706169727303053Q007461626C6503063Q00696E73657274030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F646503063Q00656D6265647303053Q007469746C6503053Q00636F6C6F72023Q00806D4C4A4103063Q006669656C647303063Q00662Q6F74657203043Q007465787403083Q004D4158492048554203093Q0074696D657374616D7003083Q004461746554696D652Q033Q006E6F7703093Q00546F49736F4461746503123Q00706F7374446973636F7264576562682Q6F6B04403Q000620012Q000400013Q0004F53Q000400010026CA3Q0007000100010004F53Q000700012Q006701045Q001254000500024Q009C000400034Q00F1000400014Q00AC00053Q000300302Q00050003000400122Q000600063Q00202Q00060006000700122Q000700083Q00122Q000800093Q00122Q000900063Q00202Q00090009000A4Q00080002000200122Q0009000B6Q00060006000900102Q00050005000600302Q0005000C000D4Q0004000100010006200103002300013Q0004F53Q002300010012C70005000E4Q0041000600034Q00050105000200070004F53Q002100010012C7000A000F3Q002082000A000A00102Q0041000B00044Q0041000C00094Q005F000A000C00010006630005001C000100020004F53Q001C00010012C7000500113Q0020280005000500124Q00073Q00014Q000800016Q00093Q000500102Q00090014000100062Q000A002C000100020004F53Q002C0001001254000A00163Q00107800090015000A00101C0009001700044Q000A3Q000100302Q000A0019001A00102Q00090018000A00122Q000A001C3Q00202Q000A000A001D4Q000A0001000200202Q000A000A001E4Q000A0002000200102Q0009001B000A4Q0008000100010010780007001300082Q006601050007000200122Q0006001F6Q00078Q000800056Q000600086Q00069Q0000017Q00193Q0003123Q006765745265736F7572636573466F6C6465722Q033Q00E2809403063Q00697061697273030B3Q004765744368696C6472656E2Q033Q0049734103083Q00496E7456616C7565030B3Q004E756D62657256616C756503053Q0056616C7565026Q00F03F03053Q007461626C6503063Q00696E7365727403043Q006E616D6503043Q004E616D652Q033Q0076616C03043Q00736F727403023Q003A2003083Q00746F737472696E6703063Q00636F6E63617403013Q000A025Q00408F4003063Q00737472696E672Q033Q00737562025Q00288F402Q033Q003Q2E029Q00523Q0012C73Q00014Q005E3Q00010002000637012Q0006000100010004F53Q00060001001254000100024Q0070000100024Q00F100015Q001232010200033Q00202Q00033Q00044Q000300046Q00023Q000400044Q00220001002057000700060005001254000900064Q006A00070009000200063701070016000100010004F53Q00160001002057000700060005001254000900074Q006A0007000900020006200107002200013Q0004F53Q00220001002082000700060008000E0500090022000100070004F53Q002200010012C70007000A3Q00200D01070007000B4Q000800016Q00093Q000200202Q000A0006000D00102Q0009000C000A00202Q000A0006000800102Q0009000E000A4Q0007000900010006630002000C000100020004F53Q000C00010012C70002000A3Q00208200020002000F2Q0041000300013Q00020B00046Q003B0002000400014Q00025Q00122Q000300036Q000400016Q00030002000500044Q003800010012C70008000A3Q00202F01080008000B4Q000900023Q00202Q000A0007000C00122Q000B00103Q00122Q000C00113Q00202Q000D0007000E4Q000C000200024Q000A000A000C4Q0008000A00010006630003002E000100020004F53Q002E00010012C70003000A3Q0020670003000300124Q000400023Q00122Q000500136Q0003000500024Q000400033Q000E2Q0014004A000100040004F53Q004A00010012C7000400153Q0020DB0004000400164Q000500033Q00122Q000600093Q00122Q000700176Q00040007000200122Q000500186Q0003000400052Q0006010400023Q000E050019004F000100040004F53Q004F000100063E01040050000100030004F53Q00500001001254000400024Q0070000400024Q005B3Q00013Q00013Q00013Q002Q033Q0076616C02083Q00208200023Q00010020820003000100010006B600030005000100020004F53Q000500012Q005800026Q0067010200014Q0070000200024Q005B3Q00017Q001C3Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D617403093Q002564D0BC202564D18103023Q00D18103043Q006E616D65031D3Q00D0A1D180D183D0B1D0B8D0BB20D0B4D0B5D180D0B5D0B2D18CD0B5D0B203053Q0076616C756503083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q00696E6C696E652Q0103193Q00D0A1D180D183D0B1D0B8D0BB20D0BAD0B0D0BCD0BDD0B5D0B903123Q0073652Q73696F6E53746F6E65734D696E6564031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0B4D0B5D1802E2903103Q0073652Q73696F6E54722Q6544726F7073031D3Q00D0A1D0BED0B1D180D0B0D0BB20D0BBD183D1822028D0BAD0B0D0BC2E2903113Q0073652Q73696F6E53746F6E6544726F707303153Q00D092D180D0B5D0BCD18F20D184D0B0D180D0BCD0B0030A3Q00D0A0D0B5D0B6D0B8D0BC030F3Q006765744661726D4D6F646554657874030E3Q005265736F757263657320283E312903173Q006765745265736F75726365734F7665724F6E6554657874012Q00453Q0012523Q00018Q0001000200122Q000100023Q00202Q00010001000300202Q00023Q00044Q00010002000200202Q00023Q00044Q000300033Q000E2Q00050012000100010004F53Q001200010012C7000400063Q00206800040004000700122Q000500086Q000600016Q000700026Q0004000700024Q000300043Q00044Q001500012Q004100045Q001254000500094Q00D00003000400052Q00F1000400074Q002A01053Q000300302Q0005000A000B00122Q0006000D3Q00122Q0007000E6Q00060002000200102Q0005000C000600302Q0005000F00104Q00063Q000300302Q0006000A001100122Q0007000D3Q0012C7000800124Q00F400070002000200102Q0006000C000700302Q0006000F00104Q00073Q000300302Q0007000A001300122Q0008000D3Q00122Q000900146Q00080002000200102Q0007000C000800302Q0007000F00102Q00F100083Q0003002Q300108000A001500122Q0009000D3Q00122Q000A00166Q00090002000200102Q0008000C000900302Q0008000F00104Q00093Q000300302Q0009000A001700102Q0009000C000300302Q0009000F00102Q00F1000A3Q000300304A000A000A001800122Q000B00196Q000B0001000200102Q000A000C000B00302Q000A000F00104Q000B3Q000300302Q000B000A001A00122Q000C001B6Q000C0001000200102Q000B000C000C0030F9000B000F001C2Q00E50004000700012Q0070000400024Q005B3Q00017Q00083Q0003153Q00446973636F72645265706F727473456E61626C656403153Q006765744661726D446973636F7264576562682Q6F6B034Q0003063Q0069706169727303153Q0067657453652Q73696F6E53746174734669656C647303053Q007461626C6503063Q00696E7365727403103Q0073656E64446973636F7264456D626564021F3Q0012C7000200013Q00063701020004000100010004F53Q000400012Q005B3Q00013Q0012C7000200024Q005E0002000100020006200102000A00013Q0004F53Q000A00010026CA0002000B000100030004F53Q000B00012Q005B3Q00014Q00F100035Q0012EB000400043Q00122Q000500056Q000500016Q00043Q000600044Q001600010012C7000900063Q0020820009000900072Q0041000A00034Q0041000B00084Q005F0009000B000100066300040011000100020004F53Q001100010012C7000400084Q0024010500026Q00068Q000700016Q000800036Q0004000800016Q00017Q00093Q0003043Q007469636B026Q00284003063Q00706C6179657203093Q00436861726163746572030E3Q0046696E6446697273744368696C6403103Q0048756D616E6F6964522Q6F745061727403043Q007461736B03043Q0077616974029A5Q99B93F011C3Q0012C7000100014Q005E00010001000200063E0102000500013Q0004F53Q00050001001254000200024Q009E0001000100020012C7000200014Q005E00020001000200060E01020019000100010004F53Q001900010012C7000200033Q00208200020002000400065E01030011000100020004F53Q00110001002057000300020005001254000500064Q006A0003000500020006200103001400013Q0004F53Q001400012Q0070000300023Q0012C7000400073Q002082000400040008001254000500094Q00D70004000200010004F53Q000600012Q0021000200024Q0070000200024Q005B3Q00017Q00053Q0003053Q00666F72636503043Q007461736B03043Q007761697403113Q00696E74652Q7275707469626C655761697403053Q0072756E496402133Q0006202Q01000B00013Q0004F53Q000B00010020820002000100010006200102000B00013Q0004F53Q000B00010012C7000200023Q0020440102000200034Q00038Q0002000200014Q000200016Q000200023Q0012C7000200044Q004100035Q00065E01040010000100010004F53Q001000010020820004000100052Q003E000200044Q001F01026Q005B3Q00017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E40030E3Q0053652Q6C4974656D52656D6F7465000F3Q00121D3Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q0009000100010004F53Q000900012Q0021000100014Q0070000100023Q00205700013Q0002001284000300053Q00122Q000400046Q000100046Q00019Q0000017Q00053Q0003113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403073Q0052656D6F746573026Q002E4003133Q00576F726C6454656C65706F727452656D6F7465000F3Q00121D3Q00013Q00206Q000200122Q000200033Q00122Q000300048Q0003000200064Q0009000100010004F53Q000900012Q0021000100014Q0070000100023Q00205700013Q0002001284000300053Q00122Q000400046Q000100046Q00019Q0000017Q00023Q0003163Q00676574576F726C6454656C65706F727452656D6F746503053Q007063612Q6C010D3Q0012C7000100014Q005E0001000100020006372Q010006000100010004F53Q000600012Q006701026Q0070000200023Q0012C7000200023Q0006D800033Q000100022Q00418Q00413Q00014Q00330102000200022Q0070000200024Q005B3Q00013Q00013Q00053Q00026Q00F03F027Q0040030C3Q00496E766F6B6553657276657203053Q007461626C6503063Q00756E7061636B000D4Q002D5Q00024Q00015Q00104Q000100014Q00015Q00104Q000200014Q000100013Q00202Q00010001000300122Q000300043Q00202Q0003000300054Q00048Q000300046Q00013Q00016Q00017Q00023Q00030D3Q0067657453652Q6C52656D6F746503053Q007063612Q6C010D3Q0012C7000100014Q005E0001000100020006372Q010006000100010004F53Q000600012Q006701026Q0070000200023Q0012C7000200023Q0006D800033Q000100022Q00418Q00413Q00014Q00330102000200022Q0070000200024Q005B3Q00013Q00013Q00073Q00026Q00F03F03083Q004974656D4E616D6503063Q00416D6F756E74030F3Q0053652Q6C4261746368416D6F756E74030A3Q004669726553657276657203053Q007461626C6503063Q00756E7061636B000F4Q00B35Q00014Q00013Q00024Q00025Q00102Q00010002000200122Q000200043Q00102Q00010003000200104Q000100014Q000100013Q00202Q00010001000500122Q000300063Q00202Q0003000300074Q00048Q000300046Q00013Q00016Q00017Q002C3Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003053Q00666F726365030F3Q004175746F53652Q6C456E61626C6564030D3Q006E2Q6564734175746F53652Q6C03093Q006661726D506861736503043Q0073652Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03103Q00636C6561724661726D5761726E696E6703093Q0073652Q6C5F6661696C030D3Q007361766553652Q6C537461746503063Q006D616E75616C2Q01030A3Q00726573756D654661726D031B3Q00D0A2D09F20D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D1833Q2E030D3Q00776F726C6454656C65706F7274030D3Q0053452Q4C5F574F524C445F4944030E3Q00636C65617253652Q6C5374617465030F3Q00707573684661726D5761726E696E6703383Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D182D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18303043Q0069646C6503363Q00D0A2D0B5D0BBD0B5D0BFD0BED180D18220D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D18320D0BDD0B520D183D0B4D0B0D0BBD181D18F03253Q00D096D0B4D191D0BC20D0B7D0B0D0B3D180D183D0B7D0BAD18320D0BCD0B8D180D0B03Q2E03133Q0077616974466F72436861726163746572487270026Q00284003123Q0053452Q4C5F574149545F41465445525F5450031F3Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0B5D180D0B2D0B0D0BDD0B0030D3Q006C6F616453652Q6C537461746503053Q00706861736503493Q00D09FD180D0BED0B4D0B0D0B6D0B020D0BFD180D0BED0B4D0BED0BBD0B6D0B8D182D181D18F20D0BFD0BED181D0BBD0B520D0BFD0B5D180D0B5D0B7D0B0D0B3D180D183D0B7D0BAD0B803203Q00D09FD180D0BED0B4D0B0D191D0BC20D180D0B5D181D183D180D181D18B3Q2E03103Q006578656375746553652Q6C4974656D7303233Q0053652Q6C4974656D52656D6F746520D0BDD0B5D0B4D0BED181D182D183D0BFD0B5D0BD026Q00F03F03063Q0072657475726E031F3Q00D092D0BED0B7D0B2D180D0B0D18220D0BDD0B020D184D0B0D180D0BC3Q2E030D3Q004641524D5F574F524C445F494403343Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0B2D0B5D180D0BDD183D182D18CD181D18F20D0BDD0B020D184D0B0D180D0BC027Q004003123Q0066696E616C697A6553652Q6C526573756D6503323Q00D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD180D0BED0B4D0B0D182D18C2028D0BDD0B5D1822072656D6F74652903213Q00D09FD180D0BED0B4D0B0D0B6D0B020D0B7D0B0D0B2D0B5D180D188D0B5D0BDD0B002CC3Q0006372Q010004000100010004F53Q000400012Q00F100026Q0041000100023Q0012C7000200013Q0006200102000A00013Q0004F53Q000A00012Q006701025Q001254000300024Q009C000200033Q00208200020001000300063701020018000100010004F53Q001800010012C7000200043Q00063701020012000100010004F53Q001200012Q006701026Q0070000200023Q0012C7000200054Q005E00020001000200063701020018000100010004F53Q001800012Q006701026Q0070000200023Q0006D800023Q000100012Q00413Q00013Q0006D800030001000100022Q00413Q00014Q00417Q0006D800040002000100022Q00413Q00014Q00418Q0021010500013Q00122Q000500013Q00122Q000500073Q00122Q000500063Q00122Q000500086Q00050001000100122Q000500096Q00050001000100122Q0005000A6Q0005000100010012C70005000B3Q0012070006000C6Q00050002000100122Q0005000D3Q00122Q000600076Q00073Q000200202Q00080001000300262Q000800340001000F0004F53Q003400012Q005800086Q0067010800013Q0010780007000E00080020820008000100100026A10008003A0001000F0004F53Q003A00012Q005800086Q0067010800013Q0010D50007001000084Q0005000700014Q000500023Q00122Q000600116Q00050002000100122Q000500123Q00122Q000600136Q00050002000200062Q00050052000100010004F53Q005200010012C7000500144Q003501050001000100122Q000500153Q00122Q0006000C3Q00122Q000700166Q0005000700014Q00055Q00122Q000500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q000600186Q000500034Q0041000500023Q0012D4000600196Q00050002000100122Q0005001A3Q00122Q0006001B6Q0005000200012Q0041000500033Q0012C70006001C4Q003301050002000200063701050066000100010004F53Q006600010012C7000500144Q00020105000100014Q00055Q00122Q000500013Q00122Q000500173Q00122Q000500066Q00055Q00122Q0006001D6Q000500033Q0012C70005001E4Q005E0005000100020006200105006D00013Q0004F53Q006D000100208200060005001F0026A100060074000100070004F53Q007400012Q006701065Q001263010600013Q00122Q000600173Q00122Q000600066Q000600013Q00122Q000700206Q000600034Q0041000600023Q001264000700216Q00060002000100122Q000600226Q000700036Q000800046Q00060008000200062Q00060081000100010004F53Q008100010012C7000700153Q0012540008000C3Q001254000900234Q005F0007000900012Q0041000700033Q001254000800244Q00330107000200020006370107008F000100010004F53Q008F00010012C7000700144Q00020107000100014Q00075Q00122Q000700013Q00122Q000700173Q00122Q000700066Q00075Q00122Q0008001D6Q000700033Q0012C70007000D3Q001254000800254Q00F100093Q0002002082000A000100030026A1000A00960001000F0004F53Q009600012Q0058000A6Q0067010A00013Q0010780009000E000A002082000A000100100026A1000A009C0001000F0004F53Q009C00012Q0058000A6Q0067010A00013Q0010D500090010000A4Q0007000900014Q000700023Q00122Q000800266Q00070002000100122Q000700123Q00122Q000800276Q00070002000200062Q000700AB000100010004F53Q00AB00010012C7000700153Q0012540008000C3Q001254000900284Q005F0007000900010012C70007001A3Q0012570108001B6Q0007000200014Q000700033Q00122Q000800296Q00070002000100122Q0007001E6Q00070001000200062Q000700BC00013Q0004F53Q00BC000100208200080007001F0026CA000800BC000100250004F53Q00BC00010012C70008002A4Q0041000900014Q0041000A00064Q005F0008000A00012Q006701085Q001259010800013Q00122Q000800173Q00122Q000800063Q00122Q0008000B3Q00122Q0009000C6Q00080002000100062Q000600C8000100010004F53Q00C800012Q006701085Q0012540009002B4Q009C000800034Q0067010800013Q0012540009002C4Q009C000800034Q005B3Q00013Q00033Q00023Q0003083Q006F6E53746174757303053Q007063612Q6C010A4Q009D00015Q0020820001000100010006202Q01000900013Q0004F53Q000900010012C7000100024Q009D00025Q0020820002000200012Q004100036Q005F0001000300012Q005B3Q00017Q00033Q0003083Q0073652Q6C5761697403053Q00666F72636503053Q0072756E4964010B3Q001251000100016Q00028Q00033Q00024Q00045Q00202Q00040004000200102Q0003000200044Q000400013Q00102Q0003000300044Q000100036Q00019Q0000017Q00033Q0003053Q00666F726365030E3Q0073652Q6C496E50726F6772652Q7303123Q0073686F756C644661726D436F6E74696E7565000B4Q009D7Q0020825Q0001000620012Q000600013Q0004F53Q000600010012C73Q00024Q00703Q00023Q0012C73Q00034Q009D000100014Q003E3Q00014Q001F017Q005B3Q00017Q00053Q00030C3Q0072756E53652Q6C4379636C6503053Q00666F7263650100030A3Q00726573756D654661726D3Q01073Q0012E2000100016Q00028Q00033Q000200302Q00030002000300302Q0003000400054Q0001000300016Q00017Q00043Q00030E3Q0073652Q6C496E50726F6772652Q73031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B003043Q007461736B03053Q00737061776E01103Q0012C7000100013Q0006202Q01000A00013Q0004F53Q000A0001000620012Q000900013Q0004F53Q000900012Q004100016Q006701025Q001254000300024Q005F0001000300012Q005B3Q00013Q0012C7000100033Q0020820001000100040006D800023Q000100012Q00418Q00D70001000200012Q005B3Q00013Q00013Q000F3Q00030B3Q004661726D456E61626C656403093Q006661726D52756E4964026Q00F03F030E3Q006661726D436865636B506175736503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030C3Q0072756E53652Q6C4379636C6503053Q00666F7263652Q01030A3Q00726573756D654661726D03083Q006F6E53746174757303133Q0068617350656E64696E6753652Q6C537461746503093Q0073746172744661726D002E3Q0012C73Q00013Q000620012Q000600013Q0004F53Q000600010012C7000100023Q0020A500010001000300129B000100024Q00672Q0100013Q001299000100043Q00122Q000100053Q00122Q000200066Q00010002000100122Q000100053Q00122Q000200076Q00010002000100122Q000100053Q00122Q000200086Q00010002000100122Q000100096Q000200026Q00033Q000300302Q0003000A000B00102Q0003000C3Q00020B00045Q00105D0003000D00044Q0001000300024Q00035Q00122Q000300043Q00064Q002600013Q0004F53Q002600010012C7000300013Q0006200103002600013Q0004F53Q002600010012C70003000E4Q005E00030001000200063701030026000100010004F53Q002600010012C70003000F4Q005A0003000100012Q009D00035Q0006200103002D00013Q0004F53Q002D00012Q009D00036Q0041000400014Q0041000500024Q005F0003000500012Q005B3Q00013Q00013Q00033Q00030A3Q0073652Q6C53746174757303063Q00506172656E7403043Q0054657874010A3Q0012C7000100013Q0006202Q01000900013Q0004F53Q000900010012C7000100013Q0020820001000100020006202Q01000900013Q0004F53Q000900010012C7000100013Q001078000100034Q005B3Q00017Q00073Q00030F3Q004175746F53652Q6C456E61626C6564030E3Q0073652Q6C496E50726F6772652Q7303043Q007469636B030F3Q006C61737453652Q6C436865636B417403113Q0053652Q6C436865636B496E74657276616C030D3Q006E2Q6564734175746F53652Q6C030B3Q0072756E4175746F53652Q6C01183Q0012C7000100013Q0006202Q01000600013Q0004F53Q000600010012C7000100023Q0006202Q01000700013Q0004F53Q000700012Q005B3Q00013Q0012C7000100034Q008F00010001000200122Q000200046Q00020001000200122Q000300053Q00062Q0002000F000100030004F53Q000F00012Q005B3Q00013Q00129B000100043Q0012C7000200064Q005E0002000100020006200102001700013Q0004F53Q001700010012C7000200074Q004100036Q00D70002000200012Q005B3Q00017Q00073Q00030B3Q004661726D456E61626C656403043Q007469636B03103Q006C6173744661726D5265706F7274417403143Q004641524D5F5245504F52545F494E54455256414C03153Q006C6F674661726D53652Q73696F6E446973636F726403153Q00D09ED182D187D191D18220D184D0B0D180D0BCD0B0023Q00806D4C4A4100123Q0012C73Q00013Q000637012Q0004000100010004F53Q000400012Q005B3Q00013Q0012C73Q00024Q008F3Q0001000200122Q000100036Q00013Q000100122Q000200043Q00062Q0001000C000100020004F53Q000C00012Q005B3Q00013Q00129B3Q00033Q00126A2Q0100053Q00122Q000200063Q00122Q000300076Q0001000300016Q00017Q000A3Q0003093Q006661726D506861736503063Q0073656172636803103Q0072656C656173654D6F757365486F6C6403113Q0063752Q72656E745461726765745061727403123Q0073686F756C644661726D436F6E74696E756503133Q0072656672657368546172676574436F756E7473030F3Q0067657456616C696454617267657473028Q0003043Q0069646C65030B3Q006875625265737457616974012A3Q00123F000100023Q00122Q000100013Q00122Q000100036Q0001000100014Q000100013Q00122Q000100046Q00015Q0012C7000200054Q004100036Q00330102000200020006200102002500013Q0004F53Q002500010012C7000200064Q003601020001000100122Q000200076Q0002000100024Q000300023Q000E2Q00080016000100030004F53Q00160001001254000300093Q00129B000300014Q0070000200023Q0012C7000300054Q004100046Q00330103000200020006370103001C000100010004F53Q001C00010004F53Q002500010012C70003000A4Q004100046Q00DD000500014Q006A00030005000200063701030023000100010004F53Q002300010004F53Q002500012Q00672Q0100013Q0004F53Q00070001001254000200093Q00129B000200014Q00F100026Q0070000200024Q005B3Q00017Q00183Q00030B3Q004661726D456E61626C6564030F3Q006661726D54696D6553746172746564028Q00030D3Q006661726D54696D65546F74616C03043Q007469636B03093Q006661726D506861736503043Q0069646C6503093Q006661726D52756E4964026Q00F03F03113Q0063752Q72656E7454617267657450617274030A3Q006163746976654E6F646503103Q006163746976655461726765744B696E6403043Q0074722Q6503053Q007063612Q6C03103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E030A3Q0072657365744175746F46030C3Q0069676E6F72656444726F707303123Q0074656C65706F7274436F2Q6E656374696F6E030F3Q006D616E75616C53652Q6C546F6B656E030E3Q0073652Q6C496E50726F6772652Q73030A3Q006661726D546872656164030C3Q0073746F70536166654D6F6465003D3Q0012C73Q00013Q000620012Q000F00013Q0004F53Q000F00010012C73Q00023Q000E050003000F00013Q0004F53Q000F00010012C73Q00043Q0012EC000100056Q00010001000200122Q000200026Q0001000100028Q000100124Q00043Q00124Q00033Q00124Q00024Q0067016Q0012473Q00013Q00124Q00073Q00124Q00063Q00124Q00083Q00206Q000900124Q00089Q003Q00124Q000A9Q003Q00124Q000B3Q00124Q000D3Q00124Q000C3Q00124Q000E3Q00122Q0001000F8Q0002000100124Q000E3Q00122Q000100108Q0002000100124Q000E3Q00122Q000100118Q0002000100124Q000E3Q00122Q000100128Q000200019Q0000124Q00133Q00124Q00143Q00064Q003200013Q0004F53Q003200010012C73Q000E3Q00020B00016Q00D73Q000200012Q00217Q00129B3Q00143Q0012C73Q00153Q00205B014Q000900124Q00159Q003Q00124Q00169Q003Q00124Q00173Q00124Q000E3Q00122Q000100188Q000200016Q00013Q00013Q00023Q0003123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q00446973636F2Q6E65637400043Q0012C73Q00013Q0020575Q00022Q00D73Q000200012Q005B3Q00017Q00013Q00030D3Q006B692Q6C4661726D4C2Q6F707300033Q0012C73Q00014Q005A3Q000100012Q005B3Q00017Q00083Q0003083Q0073746F704661726D030C3Q0073746F70536166654D6F6465030E3Q0073746F7043616D6572614C2Q6F7003183Q0064657374726F79426C6F636B65645A6F6E6556697375616C030C3Q007363722Q656E47756952656603063Q00506172656E7403053Q007063612Q6C03093Q007363722Q656E477569001E3Q00124A012Q00018Q0001000100124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00053Q00064Q001300013Q0004F53Q001300010012C73Q00053Q0020825Q0006000620012Q001300013Q0004F53Q001300010012C73Q00073Q00020B00016Q00D73Q000200010004F53Q001D00010012C73Q00083Q000620012Q001D00013Q0004F53Q001D00010012C73Q00083Q0020825Q0006000620012Q001D00013Q0004F53Q001D00010012C73Q00073Q00020B000100014Q00D73Q000200012Q005B3Q00013Q00023Q00023Q00030C3Q007363722Q656E47756952656603073Q0044657374726F7900043Q0012C73Q00013Q0020575Q00022Q00D73Q000200012Q005B3Q00017Q00023Q0003093Q007363722Q656E47756903073Q0044657374726F7900043Q0012C73Q00013Q0020575Q00022Q00D73Q000200012Q005B3Q00017Q00023Q00030B3Q00736F6674436C65616E7570030D3Q00726573746F726543616D65726100053Q0012093Q00018Q0001000100124Q00028Q000100016Q00017Q000E3Q00030D3Q006B692Q6C4661726D4C2Q6F7073030B3Q004661726D456E61626C6564030F3Q006661726D54696D655374617274656403043Q007469636B03103Q006C6173744661726D5265706F7274417403093Q006661726D52756E4964030D3Q007374617274536166654D6F646503123Q0074656C65706F7274436F2Q6E656374696F6E030A3Q0052756E5365727669636503093Q0048656172746265617403073Q00436F2Q6E656374030A3Q006661726D54687265616403043Q007461736B03053Q00737061776E001B3Q00124B3Q00018Q000100016Q00013Q00124Q00023Q00124Q00048Q0001000200124Q00033Q00124Q00048Q0001000200124Q00053Q00124Q00063Q00122Q000100076Q00010001000100122Q000100093Q00202Q00010001000A00202Q00010001000B0006D800033Q000100012Q00418Q006A00010003000200129B000100083Q0012C70001000D3Q00208200010001000E0006D800020001000100012Q00418Q00332Q010002000200129B0001000C4Q005B3Q00013Q00023Q000B3Q0003123Q0073686F756C644661726D436F6E74696E756503093Q006661726D506861736503073Q00636F2Q6C65637403043Q007761697403043Q0073652Q6C2Q033Q0068756203063Q0073656172636803043Q006D696E6503113Q0063752Q72656E745461726765745061727403053Q007063612Q6C03103Q0074656C65706F7274546F54617267657400203Q0012C73Q00014Q009D00016Q0033012Q00020002000637012Q0006000100010004F53Q000600012Q005B3Q00013Q0012C73Q00023Q0026A13Q0015000100030004F53Q001500010012C73Q00023Q0026A13Q0015000100040004F53Q001500010012C73Q00023Q0026A13Q0015000100050004F53Q001500010012C73Q00023Q0026A13Q0015000100060004F53Q001500010012C73Q00023Q0026CA3Q0016000100070004F53Q001600012Q005B3Q00013Q0012C73Q00023Q0026CA3Q001F000100080004F53Q001F00010012C73Q00093Q000620012Q001F00013Q0004F53Q001F00010012C73Q000A3Q0012C70001000B4Q00D73Q000200012Q005B3Q00017Q000D3Q0003123Q0073686F756C644661726D436F6E74696E756503053Q007063612Q6C030D3Q00697343616E63656C452Q726F7203043Q007761726E03103Q005B4D415849204855425D206661726D3A03043Q007461736B03043Q0077616974026Q00E03F03093Q006661726D52756E496403113Q0063752Q72656E7454617267657450617274030E3Q0073652Q6C496E50726F6772652Q7303093Q006661726D506861736503043Q0069646C65002E4Q0067016Q0012C7000100014Q009D00026Q00332Q01000200020006202Q01002200013Q0004F53Q002200010012C7000100023Q0006D800023Q000100022Q009D8Q00418Q00052Q01000200020006372Q010001000100010004F53Q000100010012C7000300034Q0041000400024Q00330103000200020006200103001300013Q0004F53Q001300010004F53Q002200010012C7000300043Q001223000400056Q000500026Q00030005000100122Q000300016Q00048Q00030002000200062Q0003001D000100010004F53Q001D00010004F53Q002200010012C7000300063Q002082000300030007001254000400084Q00D70003000200010004F53Q000100012Q009D00015Q0012C7000200093Q00061D2Q01002D000100020004F53Q002D00012Q0021000100013Q00129B0001000A3Q0012C70001000B3Q0006372Q01002D000100010004F53Q002D00010012540001000D3Q00129B0001000C4Q005B3Q00013Q00013Q002F3Q0003103Q006D6179626552756E4175746F53652Q6C03123Q0073686F756C644661726D436F6E74696E756503123Q006D6179626552756E4661726D5265706F727403123Q0063617074757265487562506F736974696F6E030B3Q006875625265737457616974030F3Q0067657456616C69645461726765747303133Q0072656672657368546172676574436F756E7473028Q00030E3Q0072756E536561726368506861736503043Q007461736B03043Q0077616974029A5Q99C93F030E3Q007069636B42657374546172676574030A3Q006163746976654E6F646503043Q006E6F646503103Q006163746976655461726765744B696E6403043Q006B696E6403093Q006661726D506861736503043Q006D696E65030A3Q006F72626974416E676C65030A3Q0072657365744175746F46030B3Q00676574486974626F786573030F3Q00707573684661726D5761726E696E6703093Q006E6F5F686974626F7803193Q00D0A320D186D0B5D0BBD0B820D0BDD0B5D18220486974626F78026Q00E03F03103Q00636C6561724661726D5761726E696E6703113Q0063752Q72656E7454617267657450617274026Q00F03F03043Q007469636B026Q004E40030B3Q0069734E6F6465416C697665030B3Q007570646174654175746F46030B3Q006175746F46416374697665030C3Q00737475636B5F6D696E696E67032D3Q00D094D0BED0BBD0B3D0BE20D0BDD0B520D0BBD0BED0BCD0B0D0B5D182D181D18F20E2809420D0B6D0BCD1832046030A3Q00612Q7461636B50617274029A5Q99A93F03103Q0072656C656173654D6F757365486F6C6403053Q0073746F6E6503123Q0073652Q73696F6E53746F6E65734D696E656403113Q0073652Q73696F6E54722Q65734D696E656403103Q0077616974416E645363616E44726F7073030F3Q00636F2Q6C656374412Q6C44726F707303043Q0074722Q6503133Q0073746F704368617261637465724D6F74696F6E03143Q0072657475726E546F48756241667465724E6F646500BA3Q00124F3Q00016Q00019Q000002000100124Q00026Q00019Q000002000200064Q0009000100010004F53Q000900012Q005B3Q00013Q0012C73Q00034Q0023012Q0001000100124Q00026Q00019Q000002000200064Q0011000100010004F53Q001100012Q005B3Q00014Q009D3Q00013Q000637012Q001E000100010004F53Q001E00012Q0067012Q00014Q00023Q00013Q00124Q00048Q0001000100124Q00056Q00019Q000002000200064Q001E000100010004F53Q001E00012Q005B3Q00013Q0012C73Q00064Q0040012Q0001000200122Q000100076Q0001000100014Q00015Q00262Q00010038000100080004F53Q003800010012C7000100094Q001E01028Q0001000200026Q00013Q00122Q000100026Q00028Q00010002000200062Q0001003100013Q0004F53Q003100012Q00062Q015Q0026CA00010036000100080004F53Q003600010012C70001000A3Q00208200010001000B0012540002000C4Q00D70001000200012Q005B3Q00013Q0012C7000100074Q005A0001000100010012C70001000D4Q004100026Q00332Q01000200020006372Q010042000100010004F53Q004200010012C70002000A3Q00208200020002000B0012540003000C4Q00D70002000200012Q005B3Q00013Q00208200020001000F0012400002000E3Q00202Q00020001001100122Q000200103Q00122Q000200133Q00122Q000200123Q00122Q000200083Q00122Q000200143Q00122Q000200156Q00020001000100122Q000200163Q00122Q0003000E6Q0002000200024Q000300023Q00262Q0003005B000100080004F53Q005B00010012C7000300173Q0012C1000400183Q00122Q000500196Q00030005000100122Q0003000A3Q00202Q00030003000B00122Q0004001A6Q0003000200016Q00013Q0012C70003001B3Q00120F000400186Q00030002000100202Q00030002001D00122Q0003001C3Q00122Q0003001E6Q00030001000200202Q00030003001F0012C7000400024Q009D00056Q00330104000200020006200104008700013Q0004F53Q008700010012C70004001E4Q005E00040001000200060E01040087000100030004F53Q008700010012C7000400203Q0012C70005000E4Q00330104000200020006200104008700013Q0004F53Q008700010012C7000400213Q0012C70005000E4Q00D70004000200010012C7000400223Q0006200104007C00013Q0004F53Q007C00010012C7000400173Q001254000500233Q001254000600244Q005F0004000600010004F53Q007F00010012C70004001B3Q001254000500234Q00D70004000200010012C7000400253Q00120D0005001C6Q00040002000100122Q0004000A3Q00202Q00040004000B00122Q000500266Q00040002000100044Q006300010012C7000400024Q009D00056Q00330104000200020006370104008D000100010004F53Q008D00012Q005B3Q00013Q001254000400083Q0012FF000400143Q00122Q000400276Q0004000100014Q000400043Q00122Q0004001C3Q00122Q000400103Q00262Q0004009A000100280004F53Q009A00010012C7000400293Q0020A500040004001D00129B000400293Q0004F53Q009D00010012C70004002A3Q0020A500040004001D00129B0004002A3Q0012C70004002B3Q0012580105000E6Q00068Q00040006000100122Q000400026Q00058Q00040002000200062Q000400A7000100010004F53Q00A700012Q005B3Q00013Q0012C70004002C3Q00124C0005000E6Q00068Q0004000600014Q000400043Q00122Q0004000E3Q00122Q0004002D3Q00122Q000400106Q000400043Q00122Q0004001C3Q00122Q0004002E6Q00040001000100122Q0004002F6Q00058Q00040002000200062Q000400B9000100010004F53Q00B900012Q005B3Q00014Q005B3Q00017Q00143Q0003073Q00656E61626C6564030B3Q004661726D456E61626C6564030B3Q006661726D5365636F6E6473030E3Q006765744661726D5365636F6E647303053Q00706861736503093Q006661726D506861736503053Q0074722Q6573030F3Q0063616368656454722Q65436F756E7403063Q0073746F6E657303103Q0063616368656453746F6E65436F756E7403053Q0064726F7073030F3Q0063616368656444726F70436F756E7403093Q0074722Q6544726F707303103Q0073652Q73696F6E54722Q6544726F7073030A3Q0073746F6E6544726F707303113Q0073652Q73696F6E53746F6E6544726F7073030A3Q0074722Q65734D696E656403113Q0073652Q73696F6E54722Q65734D696E6564030B3Q0073746F6E65734D696E656403123Q0073652Q73696F6E53746F6E65734D696E656400184Q00F15Q000A0012C7000100023Q0010923Q0001000100122Q000100046Q00010001000200104Q0003000100122Q000100063Q00106E3Q0005000100122Q000100083Q00104Q0007000100122Q0001000A3Q00104Q0009000100122Q0001000C3Q00104Q000B000100122Q0001000E3Q00104Q000D000100122Q000100103Q0010FE3Q000F000100122Q000100123Q00104Q0011000100122Q000100143Q00104Q001300012Q00703Q00024Q005B3Q00017Q000A3Q00030E3Q006661726D436865636B506175736503103Q0072656C656173654D6F757365486F6C64030B3Q0072656C65617365464B657903133Q0073746F704368617261637465724D6F74696F6E03113Q00426C6F636B5569447572696E674661726D030B3Q004661726D456E61626C656403043Q0067656E7603153Q004D617869487562496E76556E626C6F636B656455692Q01030C3Q0073746F70536166654D6F646500134Q0038012Q00013Q00124Q00013Q00124Q00028Q0001000100124Q00038Q0001000100124Q00048Q0001000100124Q00053Q00064Q001200013Q0004F53Q001200010012C73Q00063Q000620012Q001200013Q0004F53Q001200010012C73Q00073Q0030F93Q000800090012C73Q000A4Q005A3Q000100012Q005B3Q00017Q00073Q00030E3Q006661726D436865636B506175736503043Q0067656E7603153Q004D617869487562496E76556E626C6F636B65645569030B3Q004661726D456E61626C656403113Q00426C6F636B5569447572696E674661726D00030D3Q007374617274536166654D6F646500114Q004C016Q00124Q00013Q00124Q00023Q00206Q000300064Q001000013Q0004F53Q001000010012C73Q00043Q000620012Q001000013Q0004F53Q001000010012C73Q00053Q000620012Q001000013Q0004F53Q001000010012C73Q00023Q0030F93Q000300060012C73Q00074Q005A3Q000100012Q005B3Q00017Q00393Q0003083Q0074656C656772616D030D3Q0054454C454752414D5F4C494E4B030A3Q007363726970744C696E65031E3Q00D090D0B2D182D0BE2DD184D0B0D180D0BC20D181D0BAD180D0B8D0BFD182030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C6973745772617003083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D32026Q00F03F028Q00026Q00504003103Q004261636B67726F756E64436F6C6F723303063Q00434F4C4F525303053Q0070616E656C030F3Q00426F7264657253697A65506978656C03043Q00466F6E7403043Q00456E756D03063Q00476F7468616D03083Q005465787453697A65026Q002840030A3Q0054657874436F6C6F723303043Q0074657874030B3Q00546578745772612Q7065642Q0103043Q0054657874030C3Q005343524950545F5449544C4503013Q000A032E3Q000AD0A1D0BFD0B0D181D0B8D0B1D0BE20D187D182D0BE20D0BFD0BED0BBD18CD0B7D183D0B5D188D18CD181D18F21030B3Q004C61796F75744F7264657203063Q00506172656E7403093Q00612Q64436F726E6572026Q00204003093Q00554950612Q64696E67030A3Q0050612Q64696E67546F7003043Q005544696D026Q002440030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E675269676874030A3Q005465787442752Q746F6E026Q00444003063Q00612Q63656E74030A3Q00476F7468616D426F6C64026Q002A4003023Q00626703133Q0054656C656772616D20D0BAD0B0D0BDD0B0D0BB030F3Q004175746F42752Q746F6E436F6C6F720100027Q0040026Q002Q4003163Q004261636B67726F756E645472616E73706172656E637903053Q006D75746564026Q00084003113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E656374038E3Q00063701020004000100010004F53Q000400012Q00F100036Q0041000200033Q00208200030002000100063701030008000100010004F53Q000800010012C7000300023Q0020820004000200030006370104000C000100010004F53Q000C0001001254000400043Q0020820005000100052Q000301068Q00050002000200202Q0006000100064Q000700056Q00060002000200122Q000700073Q00202Q00070007000800122Q000800096Q00070002000200122Q0008000B3Q00202Q00080008000800122Q0009000C3Q00122Q000A000D3Q00122Q000B000D3Q00122Q000C000E6Q0008000C000200102Q0007000A000800202Q00080001001000202Q00080008001100102Q0007000F000800302Q00070012000D00122Q000800143Q00202Q00080008001300202Q00080008001500102Q00070013000800302Q00070016001700202Q00080001001000202Q00080008001900102Q00070018000800302Q0007001A001B00122Q0008001D3Q00122Q0009001E6Q000A00043Q00122Q000B001F6Q00080008000B00102Q0007001C000800302Q00070020000C00102Q00070021000600202Q0008000100224Q000900073Q00122Q000A00236Q0008000A000100122Q000800073Q00202Q00080008000800122Q000900246Q00080002000200122Q000900263Q00202Q00090009000800122Q000A000D3Q00122Q000B00276Q0009000B000200102Q00080025000900122Q000900263Q00202Q00090009000800122Q000A000D3Q00122Q000B00176Q0009000B000200102Q00080028000900122Q000900263Q00202Q00090009000800122Q000A000D3Q00122Q000B00176Q0009000B000200102Q00080029000900102Q00080021000700122Q000900073Q00202Q00090009000800122Q000A002A6Q00090002000200122Q000A000B3Q00202Q000A000A000800122Q000B000C3Q00122Q000C000D3Q00122Q000D000D3Q00122Q000E002B6Q000A000E000200102Q0009000A000A00202Q000A0001001000202Q000A000A002C00102Q0009000F000A00301A01090012000D00122Q000A00143Q00202Q000A000A001300202Q000A000A002D00102Q00090013000A00302Q00090016002E00202Q000A0001001000202Q000A000A002F00102Q00090018000A00302Q0009001C00300030F900090031003200301401090020003300102Q00090021000600202Q000A000100224Q000B00093Q00122Q000C00236Q000A000C000100122Q000A00073Q00202Q000A000A000800122Q000B00096Q000A000200020012C7000B000B3Q00208A000B000B000800122Q000C000C3Q00122Q000D000D3Q00122Q000E000D3Q00122Q000F00346Q000B000F000200102Q000A000A000B00302Q000A0035000C00122Q000B00143Q00202Q000B000B0013002082000B000B001500109F000A0013000B00302Q000A0016002700202Q000B0001001000202Q000B000B003600102Q000A0018000B00302Q000A001A001B00102Q000A001C000300302Q000A0020003700102Q000A0021000600202Q000B00090038002057000B000B00390006D8000D3Q000100022Q00413Q00034Q00413Q00094Q005F000B000D00012Q005B3Q00013Q00013Q00063Q0003053Q007063612Q6C03043Q005465787403173Q00D0A1D0BAD0BED0BFD0B8D180D0BED0B2D0B0D0BDD0BE2103043Q007461736B03053Q0064656C6179026Q00F83F000D3Q0012C73Q00013Q0006D800013Q000100012Q009D8Q00A03Q000200016Q00013Q00304Q0002000300124Q00043Q00206Q000500122Q000100063Q0006D800020001000100012Q009D3Q00014Q005F3Q000200012Q005B3Q00013Q00023Q00013Q00030C3Q00736574636C6970626F61726400043Q0012C73Q00014Q009D00016Q00D73Q000200012Q005B3Q00017Q00033Q0003063Q00506172656E7403043Q005465787403133Q0054656C656772616D20D0BAD0B0D0BDD0B0D0BB00074Q009D7Q0020825Q0001000620012Q000600013Q0004F53Q000600012Q009D7Q0030F93Q000200032Q005B3Q00017Q001A012Q00030F3Q00687562422Q6F74737472612Q706564030A3Q006C6F6164436F6E66696703073Q007461624465667303043Q006E616D65030E3Q00D093D0BBD0B0D0B2D0BDD0B0D18F03053Q007469746C6503083Q007375627469746C6503463Q00D0A3D0BFD180D0B0D0B2D0BBD0B5D0BDD0B8D0B520D184D0B0D180D0BCD0BED0BC20D0B820D181D182D0B0D182D0B8D181D182D0B8D0BAD0B020D181D0B5D181D181D0B8D0B803123Q00D09DD0B0D181D182D180D0BED0B9D0BAD0B803413Q00D094D0BED0B1D18BD187D0B02C20D0B1D0B5D0B7D0BED0BFD0B0D181D0BDD0BED181D182D18C20D0B820D0B0D0B2D182D0BE2DD0BFD180D0BED0B4D0B0D0B6D0B003073Q00446973636F726403343Q00576562682Q6F6B2C20D182D0B0D0B9D0BCD0B8D0BDD0B3D0B820D0B820D182D0B5D181D18220D0BED182D187D191D182D0BED0B2030E3Q00D09AD180D0B5D0B4D0B8D182D18B03253Q00D09E20D181D0BAD180D0B8D0BFD182D0B520D0B820D0BAD0BED0BDD182D0B0D0BAD182D18B03023Q007569030C3Q004D61786948756255494C696203063Q0063726561746503063Q00706C6179657203093Q00706C6179657247756903043Q0067656E76030C3Q005343524950545F5449544C4503073Q006775694E616D6503083Q004755495F4E414D45030D3Q007361766564506F736974696F6E030A3Q0073617665645569506F73030F3Q0064656661756C74506F736974696F6E030E3Q0044454641554C545F55495F504F5303093Q007469746C6548696E74032E3Q00456E6420E2809420D184D0B0D180D0BC20C2B72052696768744374726C20E2809420D181D0BAD180D18BD182D18C03043Q0074616273030D3Q006B657953746174757354657874030E3Q006F6E53617665506F736974696F6E03123Q007363686564756C6553617665436F6E66696703093Q006F6E44657374726F79030A3Q0066752Q6C556E6C6F6164030D3Q006F6E43616D6572615374617274030F3Q00737461727443616D6572614C2Q6F7003063Q00434F4C4F5253030C3Q00636F6E74656E74506167657303093Q00612Q64436F726E657203093Q0073776974636854616203103Q006D616B6553656374696F6E5469746C65030A3Q006D616B65546F2Q676C65030A3Q006D616B65536C69646572030E3Q006D616B655363726F2Q6C50616765030C3Q006D616B654C69737457726170030D3Q006D616B65466C6F7750616E656C030B3Q006D616B6553746174526F77030E3Q006D616B65466C6F77546F2Q676C6503093Q007363722Q656E47756903063Q007569522Q6F7403063Q007569426F6479030C3Q007363722Q656E477569526566030C3Q006D61696E4672616D6552656603133Q00666F726D617453652Q73696F6E54696D65556903103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503113Q0073652Q73696F6E537461744C6162656C73030C3Q007365744661726D537461746503083Q006D61696E50616765026Q00F03F03013Q004C03093Q0055495F4C41594F5554030D3Q00636F6E74726F6C7350616E656C03143Q00D0A3D0BFD180D0B0D0B2D0BBD0B5D0BDD0B8D0B503073Q0050414E454C5F57026Q006940028Q0003223Q00D0A1D182D0B0D180D18220D0BFD180D0B820D0B7D0B0D0B3D180D183D0B7D0BAD0B5030D3Q004175746F53746172744661726D02295C8FC2F528CC3F03113Q00D090D0B2D182D0BE20D184D0B0D180D0BC027Q0040026Q00E03F03293Q00D090D0B2D182D0BE20D0BFD180D0B820D181D0BCD0B5D0BDD0B520D181D0B5D180D0B2D0B5D180D0B0030E3Q0052656A6F696E4175746F4C6F6164026Q00084002F6285C8FC2F5E83F030C3Q0073652Q73696F6E50616E656C030C3Q00D0A1D0B5D181D181D0B8D18F03073Q0050414E454C5F48030C3Q0050414E454C5F434F4C325F58030E3Q0053452Q53494F4E5F424F44595F5903053Q007068617365030C3Q00D0A1D182D0B0D182D183D18103053Q0074722Q6573031D3Q00D0A1D180D183D0B1D0B8D0BB20D0B4D0B5D180D0B5D0B2D18CD0B5D0B203063Q0073746F6E657303193Q00D0A1D180D183D0B1D0B8D0BB20D0BAD0B0D0BCD0BDD0B5D0B903043Q006C2Q6F7403163Q00D09BD183D18220D0BDD0B020D0B7D0B5D0BCD0BBD0B5026Q00104003043Q0074696D6503153Q00D092D180D0B5D0BCD18F20D184D0B0D180D0BCD0B0026Q00144003043Q006D6F6465030A3Q00D0A0D0B5D0B6D0B8D0BC026Q001840030C3Q00736C696465727350616E656C03113Q00D092D18BD181D0BED182D0B020D0A2D09F03063Q0046552Q4C5F57030E3Q00534C494445525F50414E454C5F4803063Q00524F57335F59030D3Q00534C494445525F424F44595F59030E3Q00D094D0B5D180D0B5D0B2D18CD18F026Q002840030E3Q0054656C65706F7274486569676874030D3Q00534C494445525F595F53544550030A3Q00D09AD0B0D0BCD0BDD0B803133Q0053746F6E6554656C65706F7274486569676874030B3Q007374617475734C6162656C03083Q00496E7374616E63652Q033Q006E657703093Q00546578744C6162656C03043Q0053697A6503053Q005544696D3203073Q0056697369626C65010003063Q00506172656E7403093Q007365745363726F2Q6C03073Q0073657457726170030C3Q00D0B4D0BED0B1D18BD187D0B003073Q006D696E65426F7803053Q004672616D65030A3Q004D494E455F424F585F4803163Q004261636B67726F756E645472616E73706172656E6379030B3Q004C61796F75744F7264657203263Q00D09AD180D183D0B6D0B5D0BDD0B8D0B520D0B2D0BED0BAD180D183D0B320D186D0B5D0BBD0B8030C3Q004F72626974456E61626C6564030D3Q00544F2Q474C455F595F5354455003163Q00D090D182D0B0D0BAD0B020D0B220D186D0B5D0BBD18C030B3Q0041696D417454617267657403103Q00D09AD0BBD0B0D0B2D0B8D188D0B0204603073Q00557365464B6579030F3Q00D09AD0BBD0B8D0BA20D09BD09AD09C03083Q00557365436C69636B030A3Q00736C6964657273426F78030D3Q00534C49444552535F424F585F48031B3Q00D0A1D0BAD0BED180D0BED181D182D18C20D0BAD180D183D0B3D0B0026Q33D33F030A3Q004F7262697453702Q656403193Q00D094D0B8D0B0D0BCD0B5D182D18020D0BAD180D183D0B3D0B0026Q003E40030D3Q004F726269744469616D6574657203183Q00D0B1D0B5D0B7D0BED0BFD0B0D181D0BDD0BED181D182D18C03073Q0073616665426F78030A3Q00534146455F424F585F48031D3Q00D091D0BBD0BED0BA20554920D0BFD180D0B820D184D0B0D180D0BCD0B503113Q00426C6F636B5569447572696E674661726D03173Q00D091D0BBD0BED0BA20D182D180D0B5D0B9D0B4D0BED0B2030B3Q00426C6F636B547261646573030D3Q00D0B0D0BDD182D0B82DD182D0BF026Q001C4003073Q007A6F6E65426F78026Q004640026Q00204003163Q00D090D0BDD182D0B82DD0A2D09F20D0B7D0BED0BDD0B003133Q00426C6F636B65645A6F6E6573456E61626C6564030D3Q007A6F6E65536C69646572426F78026Q00224003153Q00D0A0D0B0D0B7D0BCD0B5D18020D0BAD183D0B1D0B0026Q003440026Q005E40030F3Q00426C6F636B65645A6F6E6553697A65030A3Q007A6F6E6542746E526F77026Q004240026Q002440030C3Q007A6F6E65506C61636542746E030A3Q005465787442752Q746F6E03103Q004261636B67726F756E64436F6C6F723303053Q0070616E656C030F3Q00426F7264657253697A65506978656C03043Q00466F6E7403043Q00456E756D030A3Q00476F7468616D426F6C6403083Q005465787453697A65026Q002640030A3Q0054657874436F6C6F723303043Q007465787403043Q005465787403243Q00D09FD0BED181D182D0B0D0B2D0B8D182D18C20D0BAD183D0B120D0B7D0B4D0B5D181D18C030F3Q004175746F42752Q746F6E436F6C6F7203113Q004D6F75736542752Q746F6E31436C69636B03073Q00436F2Q6E656374030A3Q00D186D0B5D0BDD182D18003063Q00687562426F78026Q002A40031A3Q00D09FD0B0D183D0B7D0B020D18320D181D0BFD0B0D0B2D0BDD0B0030E3Q0048756257616974456E61626C6564030E3Q00D0BFD180D0BED0B4D0B0D0B6D0B0026Q002E4003073Q0073652Q6C426F78026Q005840026Q00304003173Q00D090D0B2D182D0BE20D0BFD180D0BED0B4D0B0D0B6D0B0030F3Q004175746F53652Q6C456E61626C656403193Q00D09FD180D0BED0B2D0B5D180D0BAD0B02028D181D0B5D0BA2903113Q0053652Q6C436865636B496E74657276616C030A3Q0073652Q6C42746E526F77026Q003140030D3Q006D616E75616C53652Q6C42746E03063Q00612Q63656E7403023Q006267031B3Q00D09FD180D0BED0B4D0B0D182D18C20D181D0B5D0B9D187D0B0D181030D3Q00646973636F72645363726F2Q6C030B3Q00646973636F726457726170030A3Q00776562682Q6F6B426F78025Q0080524003043Q0063617264030C3Q00776562682Q6F6B5469746C65026Q0034C0026Q00324003083Q00506F736974696F6E030E3Q005465787458416C69676E6D656E7403043Q004C656674030B3Q00576562682Q6F6B2055524C030C3Q00776562682Q6F6B496E70757403073Q0054657874426F78026Q002Q4003103Q00436C656172546578744F6E466F63757303063Q00476F7468616D030F3Q00506C616365686F6C6465725465787403243Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F3Q2E03113Q00506C616365686F6C646572436F6C6F723303053Q006D7574656403123Q0055736572446973636F7264576562682Q6F6B030D3Q00646973636F726453746174757303103Q0063616E557365436F6E66696746696C65032E3Q00D0A1D0BED185D180D0B0D0BDD18FD0B5D182D181D18F20D0B2206D6178692D6875622D636F6E6669672E6A736F6E03473Q00D0A4D0B0D0B9D0BBD18B20D0BDD0B5D0B4D0BED181D182D183D0BFD0BDD18B20E2809420776562682Q6F6B20D0B4D0BE20D0BFD0B5D180D0B5D0B7D0B0D0BFD183D181D0BAD0B0030B3Q00646973636F72644F707473025Q00406A4003113Q00646973636F72644F7074734C61796F7574030C3Q0055494C6973744C61796F757403073Q0050612Q64696E6703043Q005544696D03093Q00536F72744F72646572030A3Q00646973636F726450616403093Q00554950612Q64696E67030A3Q0050612Q64696E67546F70030D3Q0050612Q64696E67426F2Q746F6D030B3Q0050612Q64696E674C656674030C3Q0050612Q64696E67526967687403173Q00D09ED182D187D191D182D18B20D0B220446973636F726403153Q00446973636F72645265706F727473456E61626C656403203Q00D09BD0BED0B320D0BFD180D0B820D0BED181D182D0B0D0BDD0BED0B2D0BAD0B503103Q00446973636F72644C6F674F6E53746F7003203Q00D09BD0BED0B320D0BFD0BED181D0BBD0B520D0BFD180D0BED0B4D0B0D0B6D0B803103Q00446973636F72644C6F674F6E53652Q6C030B3Q00696E74657276616C426F78026Q0020C0026Q004A4003193Q00D098D0BDD182D0B5D180D0B2D0B0D0BB2028D0BCD0B8D0BD2903143Q00446973636F72645265706F72744D696E75746573030B3Q00646973636F726442746E7303073Q007465737442746E02B81E85EB51B8DE3F03103Q00D0A2D0B5D181D18220776562682Q6F6B03073Q007361766542746E02A4703D0AD7A3E03F03123Q00D0A1D0BED185D180D0B0D0BDD0B8D182D18C030B3Q00646973636F726448696E74026Q004840030B3Q00546578745772612Q70656403CB3Q00D0A1D18ED0B4D0B020D0B8D0B4D183D18220D0BBD0BED0B3D0B820D184D0B0D180D0BCD0B03A20D181D180D183D0B1D0B8D0BB2C20D0BBD183D1822C20D0B2D180D0B5D0BCD18F2C205265736F75726365732E0AD09BD0BED0B320D0B0D0BAD182D0B8D0B2D0B0D186D0B8D0B820D181D0BAD180D0B8D0BFD182D0B02028D0B220D0BAD0BED0BDD186D0B520D184D0B0D0B9D0BBD0B02920E2809420D0BED182D0B4D0B5D0BBD18CD0BDD18BD0B92C20D0B5D0B3D0BE20D0BDD0B520D182D180D0BED0B3D0B0D0B5D0BC2E03153Q00612Q706C79576562682Q6F6B46726F6D496E70757403093Q00466F6375734C6F737403163Q006275696C644D61786948756243726564697473546162030A3Q007363726970744C696E65031E3Q00D090D0B2D182D0BE2DD184D0B0D180D0BC20D181D0BAD180D0B8D0BFD182030C3Q006F6E496E707574426567616E03083Q0066696E616C697A6503043Q007461736B03053Q00737061776E03173Q00757064617465426C6F636B65645A6F6E6556697375616C03133Q0068617350656E64696E6753652Q6C5374617465031F3Q00726573756D6550656E64696E6753652Q6C4166746572422Q6F74737472617003053Q00646566657203063Q00747970656F6603153Q004D617869487562526567697374657252656A6F696E03083Q0066756E6374696F6E03053Q007063612Q6C00FC042Q0012C73Q00013Q000620012Q000400013Q0004F53Q000400012Q005B3Q00014Q0067012Q00013Q001247012Q00013Q00124Q00028Q000100016Q00046Q00013Q000300302Q00010004000500302Q00010006000500302Q0001000700084Q00023Q000300302Q00020004000900302Q00020006000900302Q00020007000A4Q00033Q000300302Q00030004000B00302Q00030006000B00302Q00030007000C4Q00043Q000300302Q00040004000D00302Q00040006000D00302Q00040007000E6Q0004000100129B3Q00033Q0012C33Q00103Q00206Q00114Q00013Q000D00122Q000200123Q00102Q00010012000200122Q000200133Q00102Q00010013000200122Q000200143Q00102Q00010014000200122Q000200153Q00102Q00010006000200122Q000200173Q00102Q00010016000200122Q000200193Q00102Q00010018000200122Q0002001B3Q00102Q0001001A000200302Q0001001C001D00122Q000200033Q00102Q0001001E000200020B00025Q0010492Q01001F000200122Q000200213Q00102Q00010020000200122Q000200233Q00102Q00010022000200122Q000200253Q00102Q0001002400026Q0002000200124Q000F3Q00124Q000F3Q00206Q002600124Q00263Q00124Q000F3Q00206Q002700124Q00273Q00124Q000F3Q00206Q002800124Q00283Q00124Q000F3Q00206Q002900124Q00293Q00124Q000F3Q00206Q002A00124Q002A3Q00124Q000F3Q00206Q002B00124Q002B3Q00124Q000F3Q00206Q002C00124Q002C3Q00124Q000F3Q00206Q002D00124Q002D3Q00124Q000F3Q00206Q002E00124Q002E3Q00124Q000F3Q00206Q002F00124Q002F3Q00124Q000F3Q00206Q003000124Q00303Q00124Q000F3Q00206Q003100124Q00313Q00124Q000F3Q00206Q003200124Q00323Q00124Q000F3Q00206Q003300124Q00333Q00124Q000F3Q00206Q003400124Q00343Q00124Q00323Q00124Q00353Q00124Q000F3Q00206Q003300124Q00363Q00020B3Q00013Q0012263Q00379Q003Q00124Q00389Q003Q00124Q00399Q003Q00124Q003A3Q00020B3Q00023Q0012F73Q003B3Q00124Q00273Q00206Q003D00124Q003C3Q00124Q003F3Q00124Q003E3Q00124Q002F3Q00122Q0001003C3Q00122Q000200413Q00122Q0003003E3Q00202Q00030003004200122Q000400433Q00122Q000500443Q00122Q000600448Q0006000200124Q00403Q00124Q00313Q00122Q000100403Q00122Q000200453Q00122Q000300463Q00020B000400033Q0012150105003D3Q00122Q000600478Q0006000100124Q00313Q00122Q000100403Q00122Q000200486Q00035Q00020B000400043Q00128B000500493Q00122Q0006004A8Q0006000200124Q00393Q00124Q00313Q00122Q000100403Q00122Q0002004B3Q00122Q0003004C3Q00020B000400053Q0012940005004D3Q00122Q0006004E8Q0006000100124Q002F3Q00122Q0001003C3Q00122Q000200503Q00122Q0003003E3Q00202Q00030003004200122Q0004003E3Q00202Q00040004005100122Q0005003E3Q00202Q00050005005200122Q000600443Q00122Q0007003E3Q00202Q0007000700536Q0007000200124Q004F3Q00124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300553Q00122Q0004003D6Q00010004000200104Q0054000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300573Q00122Q000400496Q00010004000200104Q0056000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300593Q00122Q0004004D6Q00010004000200104Q0058000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q0003005B3Q00122Q0004005C6Q00010004000200104Q005A000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q0003005E3Q00122Q0004005F6Q00010004000200104Q005D000100124Q003A3Q00122Q000100303Q00122Q0002004F3Q00122Q000300613Q00122Q000400626Q00010004000200104Q0060000100124Q002F3Q00122Q0001003C3Q00122Q000200643Q00122Q0003003E3Q00202Q00030003006500122Q0004003E3Q00202Q00040004006600122Q000500443Q00122Q0006003E3Q00202Q00060006006700122Q0007003E3Q00202Q0007000700686Q0007000200124Q00633Q00124Q002C3Q00122Q000100633Q00122Q000200443Q00122Q000300693Q00122Q000400443Q00122Q0005006A3Q00122Q0006006B3Q00020B000700064Q0052012Q0007000100124Q002C3Q00122Q000100633Q00122Q0002003E3Q00202Q00020002006C00122Q0003006D3Q00122Q000400443Q00122Q0005006A3Q00122Q0006006E3Q00020B000700074Q00713Q0007000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q006F3Q00124Q006F3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500446Q00010005000200104Q0073000100124Q006F3Q00304Q0075007600124Q006F3Q00122Q0001003C3Q00104Q0077000100124Q002D3Q00122Q000100273Q00202Q0001000100496Q0002000200124Q00783Q00124Q002E3Q00122Q000100788Q0002000200124Q00793Q00124Q002A3Q00122Q000100793Q00122Q0002007A3Q00122Q0003003D8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q007B3Q00124Q007B3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q00050005007D4Q00010005000200104Q0073000100124Q007B3Q00304Q007E003D00124Q007B3Q00304Q007F004900124Q007B3Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q0001007B3Q00122Q000200443Q00122Q000300803Q00122Q000400813Q00020B000500084Q00B73Q0005000100124Q002B3Q00122Q0001007B3Q00122Q0002003E3Q00202Q00020002008200122Q000300833Q00122Q000400843Q00020B000500094Q0054012Q0005000100124Q002B3Q00122Q0001007B3Q00122Q0002003E3Q00202Q00020002008200202Q00020002004900122Q000300853Q00122Q000400863Q00020B0005000A4Q0054012Q0005000100124Q002B3Q00122Q0001007B3Q00122Q0002003E3Q00202Q00020002008200202Q00020002004D00122Q000300873Q00122Q000400883Q00020B0005000B4Q00BA3Q0005000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00893Q00124Q00893Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q00050005008A4Q00010005000200104Q0073000100124Q00893Q00304Q007E003D00124Q00893Q00304Q007F004D00124Q00893Q00122Q000100793Q00104Q0077000100124Q002C3Q00122Q000100893Q00122Q000200443Q00122Q0003008B3Q00122Q0004008C3Q00122Q0005004D3Q00122Q0006008D3Q00020B0007000C4Q0052012Q0007000100124Q002C3Q00122Q000100893Q00122Q0002003E3Q00202Q00020002006C00122Q0003008E3Q00122Q0004005C3Q00122Q0005008F3Q00122Q000600903Q00020B0007000D4Q0062012Q0007000100124Q002A3Q00122Q000100793Q00122Q000200913Q00122Q0003005C8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00923Q00124Q00923Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q0005000500934Q00010005000200104Q0073000100124Q00923Q00304Q007E003D00124Q00923Q00304Q007F005F00124Q00923Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q000100923Q00122Q000200443Q00122Q000300943Q00122Q000400953Q00020B0005000E4Q00B73Q0005000100124Q002B3Q00122Q000100923Q00122Q0002003E3Q00202Q00020002008200122Q000300963Q00122Q000400973Q00020B0005000F4Q00F33Q0005000100124Q002A3Q00122Q000100793Q00122Q000200983Q00122Q000300998Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q009A3Q00124Q009A3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005009B6Q00010005000200104Q0073000100124Q009A3Q00304Q007E003D00124Q009A3Q00304Q007F009C00124Q009A3Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q0001009A3Q00122Q000200443Q00122Q0003009D3Q00122Q0004009E3Q00020B000500104Q00BA3Q0005000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q009F3Q00124Q009F3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005003E3Q00202Q00050005006C4Q00010005000200104Q0073000100124Q009F3Q00304Q007E003D00124Q009F3Q00304Q007F00A000124Q009F3Q00122Q000100793Q00104Q0077000100124Q002C3Q00122Q0001009F3Q00122Q000200443Q00122Q000300A13Q00122Q000400A23Q00122Q000500A33Q00122Q000600A43Q00020B000700114Q00D93Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00A53Q00124Q00A53Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500A66Q00010005000200104Q0073000100124Q00A53Q00304Q007E003D00124Q00A53Q00304Q007F00A700124Q00A53Q00122Q000100793Q00104Q0077000100124Q00703Q00206Q007100122Q000100A98Q0002000200124Q00A83Q00124Q00A83Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q0004003D3Q00122Q000500446Q00010005000200104Q0073000100124Q00A83Q00122Q000100263Q00202Q0001000100AB00104Q00AA000100124Q00A83Q00304Q00AC004400124Q00A83Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100AF00104Q00AD000100124Q00A83Q00304Q00B000B100124Q00A83Q00122Q000100263Q00202Q0001000100B300104Q00B2000100124Q00A83Q00304Q00B400B500124Q00A83Q00304Q00B6007600124Q00A83Q00122Q000100A53Q00104Q0077000100124Q00283Q00122Q000100A83Q00122Q0002009C8Q0002000100124Q00A83Q00206Q00B700206Q00B800020B000200124Q00F33Q0002000100124Q002A3Q00122Q000100793Q00122Q000200B93Q00122Q0003006A8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00BA3Q00124Q00BA3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q0005009B6Q00010005000200104Q0073000100124Q00BA3Q00304Q007E003D00124Q00BA3Q00304Q007F00BB00124Q00BA3Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q000100BA3Q00122Q000200443Q00122Q000300BC3Q00122Q000400BD3Q00020B000500134Q00F33Q0005000100124Q002A3Q00122Q000100793Q00122Q000200BE3Q00122Q000300BF8Q0003000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00C03Q00124Q00C03Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500C16Q00010005000200104Q0073000100124Q00C03Q00304Q007E003D00124Q00C03Q00304Q007F00C200124Q00C03Q00122Q000100793Q00104Q0077000100124Q002B3Q00122Q000100C03Q00122Q000200443Q00122Q000300C33Q00122Q000400C43Q00020B000500144Q0052012Q0005000100124Q002C3Q00122Q000100C03Q00122Q0002003E3Q00202Q00020002008200122Q000300C53Q00122Q000400A23Q00122Q000500A33Q00122Q000600C63Q00020B000700154Q00D93Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00C73Q00124Q00C73Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500A66Q00010005000200104Q0073000100124Q00C73Q00304Q007E003D00124Q00C73Q00304Q007F00C800124Q00C73Q00122Q000100793Q00104Q0077000100124Q00703Q00206Q007100122Q000100A98Q0002000200124Q00C93Q00124Q00C93Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q0004003D3Q00122Q000500446Q00010005000200104Q0073000100124Q00C93Q00122Q000100263Q00202Q0001000100CA00104Q00AA000100124Q00C93Q00304Q00AC004400124Q00C93Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100AF00104Q00AD000100124Q00C93Q00304Q00B000B100124Q00C93Q00122Q000100263Q00202Q0001000100CB00104Q00B2000100124Q00C93Q00304Q00B400CC00124Q00C93Q00304Q00B6007600124Q00C93Q00122Q000100C73Q00104Q0077000100124Q00283Q00122Q000100C93Q00122Q0002009C8Q0002000100124Q00C93Q00206Q00B700206Q00B800020B000200164Q00FC3Q0002000100124Q002D3Q00122Q000100273Q00202Q00010001004D6Q0002000200124Q00CD3Q00124Q002E3Q00122Q000100CD8Q0002000200124Q00CE3Q00124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00CF3Q00124Q00CF3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500D06Q00010005000200104Q0073000100124Q00CF3Q00122Q000100263Q00202Q0001000100D100104Q00AA000100124Q00CF3Q00304Q00AC004400124Q00CF3Q00304Q007F003D00124Q00CF3Q00122Q000100CE3Q00104Q0077000100124Q00283Q00122Q000100CF3Q00122Q000200A78Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00D23Q00124Q00D23Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300D33Q00122Q000400443Q00122Q000500D46Q00010005000200104Q0073000100124Q00D23Q00122Q000100743Q00202Q00010001007100122Q000200443Q00122Q000300A73Q00122Q000400443Q00122Q0005009C6Q00010005000200104Q00D5000100124Q00D23Q00304Q007E003D00124Q00D23Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100AF00104Q00AD000100124Q00D23Q00304Q00B000B100124Q00D23Q00122Q000100263Q00202Q0001000100B300104Q00B2000100124Q00D23Q00122Q000100AE3Q00202Q0001000100D600202Q0001000100D700104Q00D6000100121B012Q00D23Q00304Q00B400D800124Q00D23Q00122Q000100CF3Q00104Q0077000100124Q00703Q00206Q007100122Q000100DA8Q0002000200124Q00D93Q0012C73Q00D93Q0012CE000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300D33Q00122Q000400443Q00122Q0005008F6Q00010005000200104Q0073000100124Q00D93Q00122Q000100743Q002082000100010071001248000200443Q00122Q000300A73Q00122Q000400443Q00122Q000500DB6Q00010005000200104Q00D5000100124Q00D93Q00122Q000100263Q00202Q0001000100AB00104Q00AA00010012C73Q00D93Q0030343Q00AC004400124Q00D93Q00304Q00DC007600124Q00D93Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100DD00104Q00AD000100124Q00D93Q00304Q00B000A70012C73Q00D93Q001218000100263Q00202Q0001000100B300104Q00B2000100124Q00D93Q00304Q00DE00DF00124Q00D93Q00122Q000100263Q00202Q0001000100E100104Q00E0000100124Q00D93Q0012C7000100E23Q0010163Q00B4000100124Q00D93Q00122Q000100AE3Q00202Q0001000100D600202Q0001000100D700104Q00D6000100124Q00D93Q00122Q000100CF3Q00104Q0077000100124Q00283Q0012C7000100D93Q00126C0102009C8Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q00E33Q00124Q00E33Q00122Q000100743Q00202Q0001000100710012540002003D3Q001227000300443Q00122Q000400443Q00122Q000500C26Q00010005000200104Q0073000100121A3Q00E33Q00304Q007E003D00124Q00E33Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100DD00104Q00AD000100124Q00E33Q00304Q00B000A700124Q00E33Q00122Q000100263Q00202Q0001000100E100104Q00B2000100124Q00E33Q00122Q000100AE3Q00202Q0001000100D600202Q0001000100D700104Q00D6000100124Q00E33Q00122Q000100E46Q00010001000200062Q0001007003013Q0004F53Q00700301001254000100E53Q0006372Q010071030100010004F53Q00710301001254000100E63Q0010783Q00B40001001242012Q00E33Q00304Q007F004900124Q00E33Q00122Q000100CE3Q00104Q0077000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00E73Q00124Q00E73Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500E86Q00010005000200104Q0073000100124Q00E73Q00122Q000100263Q00202Q0001000100D100104Q00AA000100124Q00E73Q00304Q00AC004400124Q00E73Q00304Q007F004D00124Q00E73Q00122Q000100CE3Q00104Q0077000100124Q00283Q00122Q000100E73Q00122Q000200A78Q0002000100124Q00703Q00206Q007100122Q000100EA8Q0002000200124Q00E93Q00124Q00E93Q00122Q000100EC3Q00202Q00010001007100122Q000200443Q00122Q0003005C6Q00010003000200104Q00EB000100124Q00E93Q00122Q000100AE3Q00202Q0001000100ED00202Q00010001007F00104Q00ED000100124Q00E93Q00122Q000100E73Q00104Q0077000100124Q00703Q00206Q007100122Q000100EF8Q0002000200124Q00EE3Q00124Q00EE3Q00122Q000100EC3Q00202Q00010001007100122Q000200443Q00122Q0003009C6Q00010003000200104Q00F0000100124Q00EE3Q00122Q000100EC3Q00202Q00010001007100122Q000200443Q00122Q0003009C6Q00010003000200104Q00F1000100124Q00EE3Q00122Q000100EC3Q00202Q00010001007100122Q000200443Q00122Q0003005C6Q00010003000200104Q00F200010012C73Q00EE3Q0012F0000100EC3Q00202Q00010001007100122Q000200443Q00122Q0003005C6Q00010003000200104Q00F3000100124Q00EE3Q00122Q000100E73Q00104Q0077000100124Q00313Q00122Q000100E73Q00122Q000200F43Q00122Q000300F53Q00020B000400173Q00122F0005003D8Q0005000100124Q00313Q00122Q000100E73Q00122Q000200F63Q00122Q000300F73Q00020B000400183Q00122F000500498Q0005000100124Q00313Q00122Q000100E73Q00122Q000200F83Q00122Q000300F93Q00020B000400193Q0012B50005004D8Q0005000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00FA3Q00124Q00FA3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300FB3Q00122Q000400443Q00122Q000500FC6Q00010005000200104Q0073000100124Q00FA3Q00304Q007E003D00124Q00FA3Q00304Q007F005C00124Q00FA3Q00122Q000100E73Q00104Q0077000100124Q002C3Q00122Q000100FA3Q00122Q000200443Q00122Q000300FD3Q00122Q0004003D3Q00122Q000500A33Q00122Q000600FE3Q00020B0007001A4Q0041012Q0007000100124Q00703Q00206Q007100122Q0001007C8Q0002000200124Q00FF3Q00124Q00FF3Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q000500A66Q00010005000200104Q0073000100124Q00FF3Q00304Q007E003D00124Q00FF3Q00304Q007F005F00124Q00FF3Q00122Q000100CE3Q00104Q0077000100124Q00703Q00206Q007100122Q000100A98Q0002000200125Q00012Q00125Q00012Q00122Q000100743Q00202Q00010001007100122Q0002002Q012Q00122Q000300443Q00122Q0004003D3Q00122Q000500446Q00010005000200104Q0073000100125Q00012Q00122Q000100263Q00202Q0001000100CA00104Q00AA000100125Q00012Q00122Q000100443Q00104Q00AC000100125Q00012Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100AF00104Q00AD000100125Q00012Q00122Q000100B13Q00104Q00B0000100125Q00012Q00122Q000100263Q00202Q0001000100CB00104Q00B2000100125Q00012Q00122Q00010002012Q00104Q00B4000100125Q00015Q00015Q00104Q00B6000100125Q00012Q00122Q000100FF3Q00104Q0077000100124Q00283Q00122Q00012Q00012Q00122Q0002009C8Q0002000100124Q00703Q00206Q007100122Q000100A98Q0002000200124Q0003012Q00124Q0003012Q00122Q000100743Q00202Q00010001007100122Q0002002Q012Q00122Q000300443Q00122Q0004003D3Q00122Q000500444Q006A000100050002001028012Q0073000100124Q0003012Q00122Q000100743Q00202Q00010001007100122Q00020004012Q00122Q000300443Q00122Q000400443Q00122Q000500446Q00010005000200104Q00D5000100124Q0003012Q00122Q000100263Q00202Q0001000100AB00104Q00AA000100124Q0003012Q00122Q000100443Q00104Q00AC000100124Q0003012Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100AF00104Q00AD000100124Q0003012Q00122Q000100B13Q00104Q00B0000100124Q0003012Q00122Q000100263Q00202Q0001000100B300104Q00B2000100124Q0003012Q00122Q00010005012Q00104Q00B4000100124Q0003015Q00015Q00104Q00B6000100124Q0003012Q00122Q000100FF3Q00104Q0077000100124Q00283Q00122Q00010003012Q00122Q0002009C8Q0002000100124Q00703Q00206Q007100122Q000100728Q0002000200124Q0006012Q00124Q0006012Q00122Q000100743Q00202Q00010001007100122Q0002003D3Q00122Q000300443Q00122Q000400443Q00122Q00050007015Q00010005000200104Q0073000100124Q0006012Q00122Q0001003D3Q00104Q007E000100124Q0006012Q00122Q000100AE3Q00202Q0001000100AD00202Q0001000100DD00104Q00AD000100124Q0006012Q00122Q000100A73Q00104Q00B0000100124Q0006012Q00122Q000100263Q00202Q0001000100E100104Q00B2000100124Q0006012Q00122Q00010008015Q000200018Q0001000200124Q0006012Q00122Q000100AE3Q00202Q0001000100D600202Q0001000100D700104Q00D600010012C73Q0006012Q00127600010009012Q00104Q00B4000100124Q0006012Q00122Q000100623Q00104Q007F000100124Q0006012Q00122Q000100CE3Q00104Q0077000100020B3Q001B3Q00123A3Q000A012Q00124Q00D93Q00122Q0001000B019Q000100206Q00B800020B0002001C4Q005F3Q000200010012C73Q0003012Q0020825Q00B70020575Q00B800020B0002001D4Q005F3Q000200010012C74Q00012Q0020825Q00B70020575Q00B800020B0002001E4Q00393Q0002000100124Q000C012Q00122Q000100273Q00122Q0002005C6Q0001000100024Q00023Q000400122Q000300263Q00102Q00020026000300122Q0003002D3Q00102Q0002002D000300122Q0003002E3Q00102Q0002002E000300122Q000300283Q00102Q0002002800034Q00033Q000100122Q0004000D012Q00122Q0005000E015Q0003000400056Q0003000100124Q000F3Q00122Q0001000F019Q000100020B0001001F4Q00863Q0002000100124Q000F3Q00122Q00010010019Q00016Q0001000100124Q0011012Q00122Q00010012019Q000100020B000100204Q00243Q0002000100124Q0013017Q0001000100124Q0014017Q0001000200064Q00E304013Q0004F53Q00E304010012C73Q0015013Q005A3Q000100010004F53Q00EB04010012C73Q00463Q000620012Q00EB04013Q0004F53Q00EB04010012C73Q0011012Q00125400010016013Q002C5Q000100020B000100214Q00D73Q000200010012C73Q004C3Q000620012Q00FB04013Q0004F53Q00FB04010012C73Q0017012Q0012DF000100143Q00122Q00020018015Q0001000100026Q0002000200122Q00010019012Q00064Q00FB040100010004F53Q00FB04010012C73Q001A012Q0012C7000100143Q00125400020018013Q002C0001000100022Q00D73Q000200012Q005B3Q00013Q00223Q00053Q0003043Q0067656E76030E3Q004D6178694875624B65794761746503063Q00747970656F6603103Q006765744B65795374617475735465787403083Q0066756E6374696F6E000F3Q0012C73Q00013Q0020825Q0002000620012Q000C00013Q0004F53Q000C00010012C7000100033Q00208200023Q00042Q00332Q01000200020026CA0001000C000100050004F53Q000C000100208200013Q00042Q00BF000100014Q001F2Q016Q0021000100014Q0070000100024Q005B3Q00017Q00093Q00030E3Q006765744661726D5365636F6E647303043Q006D61746803053Q00666C2Q6F72026Q004E40028Q0003063Q00737472696E6703063Q00666F726D6174030B3Q002564D0BC2025303264D18103023Q00D18100153Q0012D23Q00018Q0001000200122Q000100023Q00202Q00010001000300202Q00023Q00044Q00010002000200202Q00023Q0004000E2Q00050010000100010004F53Q001000010012C7000300063Q00200100030003000700122Q000400086Q000500016Q000600026Q000300066Q00036Q004100035Q001254000400094Q00D00003000300042Q0070000300024Q005B3Q00017Q000D3Q00030B3Q004661726D456E61626C656403103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C6503093Q0073746172744661726D03113Q0073652Q73696F6E54722Q65734D696E6564028Q0003123Q0073652Q73696F6E53746F6E65734D696E6564030E3Q006765744661726D5365636F6E6473026Q00344003083Q0073746F704661726D03103Q00446973636F72644C6F674F6E53746F7003043Q007461736B03053Q00646566657201353Q000620012Q001100013Q0004F53Q001100010012C7000100013Q0006202Q01000600013Q0004F53Q000600012Q005B3Q00014Q00672Q0100013Q00124B2Q0100023Q00122Q000100036Q000200016Q000300016Q0001000300014Q00015Q00122Q000100023Q00122Q000100046Q00010001000100044Q003400010012C7000100013Q0006372Q010015000100010004F53Q001500012Q005B3Q00013Q0012C7000100053Q000E1001060020000100010004F53Q002000010012C7000100073Q000E1001060020000100010004F53Q002000010012C7000100084Q005E000100010002000E1001090020000100010004F53Q002000012Q005800016Q00672Q0100014Q00CF000200013Q00122Q000200023Q00122Q000200036Q00038Q000400016Q0002000400014Q00025Q00122Q000200023Q00122Q0002000A6Q00020001000100062Q0001003400013Q0004F53Q003400010012C70002000B3Q0006200102003400013Q0004F53Q003400010012C70002000C3Q00208200020002000D00020B00036Q00D70002000200012Q005B3Q00013Q00013Q00013Q0003053Q007063612Q6C00043Q0012C73Q00013Q00020B00016Q00D73Q000200012Q005B3Q00013Q00013Q00033Q0003153Q006C6F674661726D53652Q73696F6E446973636F7264031D3Q00D0A4D0B0D180D0BC20D0BED181D182D0B0D0BDD0BED0B2D0BBD0B5D0BD023Q008087E96C4100053Q00126A012Q00013Q00122Q000100023Q00122Q000200038Q000200016Q00017Q00023Q00030D3Q004175746F53746172744661726D03123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q0003103Q006661726D546F2Q676C6553696C656E74030C3Q007365744661726D537461746501083Q0012C7000100013Q0006202Q01000400013Q0004F53Q000400012Q005B3Q00013Q0012C7000100024Q004100026Q00D70001000200012Q005B3Q00017Q00073Q00030E3Q0052656A6F696E4175746F4C6F616403123Q007363686564756C6553617665436F6E66696703063Q00747970656F6603043Q0067656E7603153Q004D617869487562526567697374657252656A6F696E03083Q0066756E6374696F6E03053Q007063612Q6C01103Q00129B3Q00013Q0012C7000100024Q005A000100010001000620012Q000F00013Q0004F53Q000F00010012C7000100033Q0012C7000200043Q0020820002000200052Q00332Q01000200020026CA0001000F000100060004F53Q000F00010012C7000100073Q0012C7000200043Q0020820002000200052Q00D70001000200012Q005B3Q00017Q00023Q00030E3Q0054656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q0003133Q0053746F6E6554656C65706F727448656967687403123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q00030C3Q004F72626974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q00030B3Q0041696D417454617267657403123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q0003073Q00557365464B657903123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00033Q0003083Q00557365436C69636B03103Q0072656C656173654D6F757365486F6C6403123Q007363686564756C6553617665436F6E66696701083Q00129B3Q00013Q000620012Q000500013Q0004F53Q000500010012C7000100024Q005A0001000100010012C7000100034Q005A0001000100012Q005B3Q00017Q00023Q00030A3Q004F7262697453702Q656403123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q00030D3Q004F726269744469616D6574657203123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q0003113Q00426C6F636B5569447572696E674661726D03123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00053Q00030B3Q00426C6F636B547261646573030B3Q004661726D456E61626C6564030A3Q007363616E54726164657303093Q00706C6179657247756903123Q007363686564756C6553617665436F6E666967010A3Q00129B3Q00013Q0012C7000100023Q0006202Q01000700013Q0004F53Q000700010012C7000100033Q0012C7000200044Q00D70001000200010012C7000100054Q005A0001000100012Q005B3Q00017Q00033Q0003133Q00426C6F636B65645A6F6E6573456E61626C656403173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E66696701063Q00129B3Q00013Q001209000100026Q00010001000100122Q000100036Q0001000100016Q00017Q00053Q00030F3Q00426C6F636B65645A6F6E6553697A6503043Q006D61746803053Q00666C2Q6F7203173Q00757064617465426C6F636B65645A6F6E6556697375616C03123Q007363686564756C6553617665436F6E666967010A3Q001235000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q00010001000100122Q000100056Q0001000100016Q00017Q00083Q0003163Q00736574426C6F636B65645A6F6E654174506C61796572030C3Q007A6F6E65506C61636542746E03043Q0054657874031B3Q00D09AD183D0B120D183D181D182D0B0D0BDD0BED0B2D0BBD0B5D0BD03043Q007461736B03053Q0064656C6179026Q33F33F03193Q00D09DD0B5D18220D0BFD0B5D180D181D0BED0BDD0B0D0B6D0B0000F3Q0012C73Q00014Q005E3Q00010002000620012Q000C00013Q0004F53Q000C00010012C73Q00023Q0030F93Q000300040012C73Q00053Q0020825Q0006001254000100073Q00020B00026Q005F3Q000200010004F53Q000E00010012C73Q00023Q0030F93Q000300082Q005B3Q00013Q00013Q00043Q00030C3Q007A6F6E65506C61636542746E03063Q00506172656E7403043Q005465787403243Q00D09FD0BED181D182D0B0D0B2D0B8D182D18C20D0BAD183D0B120D0B7D0B4D0B5D181D18C00073Q0012C73Q00013Q0020825Q0002000620012Q000600013Q0004F53Q000600010012C73Q00013Q0030F93Q000300042Q005B3Q00017Q00023Q00030E3Q0048756257616974456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q00030F3Q004175746F53652Q6C456E61626C656403123Q007363686564756C6553617665436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00043Q0003113Q0053652Q6C436865636B496E74657276616C03043Q006D61746803053Q00666C2Q6F7203123Q007363686564756C6553617665436F6E66696701083Q0012DA000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100046Q0001000100016Q00017Q000C3Q00030E3Q0073652Q6C496E50726F6772652Q73030A3Q0073652Q6C53746174757303043Q0054657874031E3Q00D0A3D0B6D0B520D0B8D0B4D191D18220D0BFD180D0BED0B4D0B0D0B6D0B0030A3Q0054657874436F6C6F723303063Q00434F4C4F52532Q033Q00726564030D3Q006D616E75616C53652Q6C42746E03113Q00D09FD180D0BED0B4D0B0D0B6D0B03Q2E031B3Q00D0A2D09F20D0BDD0B020D0BFD180D0BED0B4D0B0D0B6D1833Q2E03053Q006D75746564030D3Q0072756E4D616E75616C53652Q6C00163Q0012C73Q00013Q000620012Q000A00013Q0004F53Q000A00010012C73Q00023Q0030C93Q0003000400124Q00023Q00122Q000100063Q00202Q00010001000700104Q000500016Q00013Q0012C73Q00083Q00307D3Q0003000900124Q00023Q00304Q0003000A00124Q00023Q00122Q000100063Q00202Q00010001000B00104Q0005000100124Q000C3Q00020B00016Q00D73Q000200012Q005B3Q00013Q00013Q000A3Q00030D3Q006D616E75616C53652Q6C42746E03043Q0054657874031B3Q00D09FD180D0BED0B4D0B0D182D18C20D181D0B5D0B9D187D0B0D181030A3Q0073652Q6C537461747573030C3Q00D093D0BED182D0BED0B2D0BE030C3Q00D09ED188D0B8D0B1D0BAD0B0030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q0072656402173Q0012C7000200013Q0030F90002000200030012C7000200043Q00063E0103000B000100010004F53Q000B0001000620012Q000A00013Q0004F53Q000A0001001254000300053Q0006370103000B000100010004F53Q000B0001001254000300063Q0010780002000200030012C7000200043Q000620012Q001300013Q0004F53Q001300010012C7000300083Q00208200030003000900063701030015000100010004F53Q001500010012C7000300083Q00208200030003000A0010780002000700032Q005B3Q00017Q00053Q0003153Q00446973636F72645265706F727473456E61626C656403143Q004641524D5F5245504F52545F494E54455256414C03143Q00446973636F72645265706F72744D696E75746573026Q004E4003113Q0073617665446973636F7264436F6E66696701073Q00126D3Q00013Q00122Q000100033Q00202Q00010001000400122Q000100023Q00122Q000100056Q0001000100016Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53746F7003113Q0073617665446973636F7264436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00023Q0003103Q00446973636F72644C6F674F6E53652Q6C03113Q0073617665446973636F7264436F6E66696701043Q00129B3Q00013Q0012C7000100024Q005A0001000100012Q005B3Q00017Q00063Q0003143Q00446973636F72645265706F72744D696E7574657303043Q006D61746803053Q00666C2Q6F7203143Q004641524D5F5245504F52545F494E54455256414C026Q004E4003113Q0073617665446973636F7264436F6E666967010B3Q0012EE000100023Q00202Q0001000100034Q00028Q00010002000200122Q000100013Q00122Q000100013Q00202Q00010001000500122Q000100043Q00122Q000100066Q0001000100016Q00017Q00083Q0003123Q0055736572446973636F7264576562682Q6F6B030C3Q00776562682Q6F6B496E70757403043Q005465787403043Q006773756203043Q005E25732B034Q0003043Q0025732B2403113Q0073617665446973636F7264436F6E666967000E3Q00123A012Q00023Q00206Q000300206Q000400122Q000200053Q00122Q000300068Q0003000200206Q000400122Q000200073Q00122Q000300068Q0003000200124Q00013Q00124Q00088Q000100016Q00017Q00013Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757400033Q0012C73Q00014Q005A3Q000100012Q005B3Q00017Q000A3Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E707574030D3Q00646973636F726453746174757303043Q005465787403123Q00D0A1D0BED185D180D0B0D0BDD0B5D0BDD0BE030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E7403043Q007461736B03053Q0064656C6179027Q0040000E3Q00125F012Q00018Q0001000100124Q00023Q00304Q0003000400124Q00023Q00122Q000100063Q00202Q00010001000700104Q0005000100124Q00083Q00206Q000900122Q0001000A3Q00020B00026Q005F3Q000200012Q005B3Q00013Q00013Q00093Q00030D3Q00646973636F726453746174757303063Q00506172656E7403043Q005465787403103Q0063616E557365436F6E66696746696C65032E3Q00D0A1D0BED185D180D0B0D0BDD18FD0B5D182D181D18F20D0B2206D6178692D6875622D636F6E6669672E6A736F6E03473Q00D0A4D0B0D0B9D0BBD18B20D0BDD0B5D0B4D0BED181D182D183D0BFD0BDD18B20E2809420776562682Q6F6B20D0B4D0BE20D0BFD0B5D180D0B5D0B7D0B0D0BFD183D181D0BAD0B0030A3Q0054657874436F6C6F723303063Q00434F4C4F525303053Q006D7574656400133Q0012C73Q00013Q0020825Q0002000620012Q001200013Q0004F53Q001200010012C73Q00013Q0012C7000100044Q005E0001000100020006202Q01000C00013Q0004F53Q000C0001001254000100053Q0006372Q01000D000100010004F53Q000D0001001254000100063Q0010783Q000300010012C73Q00013Q0012C7000100083Q0020820001000100090010783Q000700012Q005B3Q00017Q00163Q0003153Q00612Q706C79576562682Q6F6B46726F6D496E70757403103Q0073656E64446973636F7264456D62656403153Q006765744661726D446973636F7264576562682Q6F6B03113Q00D0A2D0B5D181D182204D41584920485542023Q00806D4C4A4103043Q006E616D6503103Q00D09FD180D0BED0B2D0B5D180D0BAD0B003053Q0076616C756503393Q00D095D181D0BBD0B820D0B2D0B8D0B4D0B8D188D18C20D18DD182D0BE20E2809420776562682Q6F6B20D180D0B0D0B1D0BED182D0B0D0B5D18203063Q00696E6C696E65010003103Q00D098D0BDD182D0B5D180D0B2D0B0D0BB03083Q00746F737472696E6703143Q00446973636F72645265706F72744D696E7574657303073Q0020D0BCD0B8D0BD2Q01030D3Q00646973636F726453746174757303043Q0054657874030A3Q0054657874436F6C6F723303063Q00434F4C4F525303063Q00612Q63656E742Q033Q0072656400243Q00128C3Q00018Q0001000100124Q00023Q00122Q000100036Q00010001000200122Q000200043Q00122Q000300056Q000400026Q00053Q000300302Q00050006000700302Q00050008000900302Q0005000A000B4Q00063Q000300302Q00060006000C00122Q0007000D3Q00122Q0008000E6Q00070002000200122Q0008000F6Q00070007000800102Q00060008000700302Q0006000A00104Q0004000200012Q00E83Q000400010012C7000200113Q0010780002001200010012C7000200113Q000620012Q002000013Q0004F53Q002000010012C7000300143Q00208200030003001500063701030022000100010004F53Q002200010012C7000300143Q0020820003000300160010780002001300032Q005B3Q00017Q00093Q0003073Q004B6579436F646503063Q00484F544B455903043Q007469636B03043Q0067656E7603133Q004D6178694875624C617374486F746B65794174028Q0002CD5QCCDC3F030C3Q007365744661726D5374617465030B3Q004661726D456E61626C656401173Q00208200013Q00010012C7000200023Q0006E900010005000100020004F53Q000500012Q005B3Q00013Q0012C7000100034Q005E0001000100020012C7000200043Q0020820002000200050006370102000C000100010004F53Q000C0001001254000200065Q0001020001000200264601020010000100070004F53Q001000012Q005B3Q00013Q0012C7000200043Q00101301020005000100122Q000200083Q00122Q000300096Q000300036Q0002000200016Q00017Q00263Q0003093Q007363722Q656E47756903063Q00506172656E74030A3Q006163746976654E6F646503093Q006661726D506861736503043Q007761697403073Q00636F2Q6C656374030F3Q0063616368656444726F70436F756E74030D3Q0066696E6444726F70734E656172028Q00030A3Q0050484153455F54455854030B3Q006175746F46416374697665030D3Q0020C2B720D0B0D0B2D182D0BE46034Q00030F3Q006765744661726D4D6F64655465787403113Q0073652Q73696F6E537461744C6162656C7303053Q00706861736503043Q005465787403053Q0074722Q657303083Q00746F737472696E6703113Q0073652Q73696F6E54722Q65734D696E656403063Q0073746F6E657303123Q0073652Q73696F6E53746F6E65734D696E656403043Q006C2Q6F7403043Q0074696D6503133Q00666F726D617453652Q73696F6E54696D65556903043Q006D6F6465030B3Q007374617475734C6162656C03073Q0056697369626C65030F3Q004175746F53652Q6C456E61626C656403143Q0067657453652Q6C5472692Q676572416D6F756E7403063Q00737472696E6703063Q00666F726D617403083Q00207C2025733A256403233Q002573207C20D0B43A256420D0BA3A2564207C202573207C20D0BBD183D1823A25642573030F3Q0063616368656454722Q65436F756E7403103Q0063616368656453746F6E65436F756E7403043Q007461736B029A5Q99D93F00823Q0012C73Q00013Q0020825Q0002000620012Q008100013Q0004F53Q008100010012C73Q00033Q000620012Q001300013Q0004F53Q001300010012C73Q00043Q0026A13Q000D000100050004F53Q000D00010012C73Q00043Q0026CA3Q0013000100060004F53Q001300010012C73Q00083Q00125C000100038Q000200029Q0000124Q00073Q00044Q001500010012543Q00093Q00129B3Q00073Q0012C73Q000A3Q0012C7000100044Q002C5Q0001000637012Q001B000100010004F53Q001B00010012C73Q00043Q0012C70001000B3Q0006202Q01002100013Q0004F53Q002100010012540001000C3Q0006372Q010022000100010004F53Q002200010012540001000D3Q0012C70002000E4Q005E0002000100020012C70003000F3Q0020820003000300100006200103002E00013Q0004F53Q002E00010012C70003000F3Q00203C0003000300104Q00048Q000500016Q00040004000500102Q0003001100040012C70003000F3Q0020820003000300120006200103003800013Q0004F53Q003800010012C70003000F3Q00202E00030003001200122Q000400133Q00122Q000500146Q00040002000200102Q0003001100040012C70003000F3Q0020820003000300150006200103004200013Q0004F53Q004200010012C70003000F3Q00202E00030003001500122Q000400133Q00122Q000500166Q00040002000200102Q0003001100040012C70003000F3Q0020820003000300170006200103004C00013Q0004F53Q004C00010012C70003000F3Q00202E00030003001700122Q000400133Q00122Q000500076Q00040002000200102Q0003001100040012C70003000F3Q0020820003000300180006200103005500013Q0004F53Q005500010012C70003000F3Q0020820003000300180012C7000400194Q005E0004000100020010780003001100040012C70003000F3Q00208200030003001A0006200103005C00013Q0004F53Q005C00010012C70003000F3Q00208200030003001A0010780003001100020012C70003001B3Q0006200103007C00013Q0004F53Q007C00010012C70003001B3Q00208200030003001C0006200103007C00013Q0004F53Q007C00010012540003000D3Q0012C70004001D3Q0006200104007000013Q0004F53Q007000010012C70004001E4Q00DC00040001000500122Q0006001F3Q00202Q00060006002000122Q000700216Q000800056Q000900046Q0006000900024Q000300063Q0012C70004001B3Q0012950005001F3Q00202Q00050005002000122Q000600226Q000700023Q00122Q000800233Q00122Q000900246Q000A5Q00122Q000B00076Q000C00036Q0005000C000200102Q0004001100050012C7000300253Q002082000300030005001254000400264Q00D70003000200010004F55Q00012Q005B3Q00017Q00033Q0003103Q006661726D546F2Q676C6553696C656E74030D3Q007365744661726D546F2Q676C65030C3Q007365744661726D5374617465000C4Q00153Q00013Q00124Q00013Q00124Q00026Q000100016Q000200018Q000200019Q0000124Q00013Q00124Q00036Q000100018Q000200016Q00017Q00093Q00030C3Q00656E73757265506C6179657203043Q007761726E03393Q005B4D415849204855425D20D09DD0B520D183D0B4D0B0D0BBD0BED181D18C20D0BFD0BED0BBD183D187D0B8D182D18C20506C6179657247756903053Q007072696E74031D3Q005B4D415849204855425D20D0B7D0B0D0BFD183D181D0BA2055493Q2E03053Q007063612Q6C03103Q00622Q6F7473747261704D617869487562030F3Q00687562422Q6F74737472612Q70656403273Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0B7D0B0D0BFD183D181D0BAD0B03A00173Q0012C73Q00014Q005E3Q00010002000637012Q0008000100010004F53Q000800010012C73Q00023Q001254000100034Q00D73Q000200012Q005B3Q00013Q0012C73Q00043Q001236000100058Q0002000100124Q00063Q00122Q000100078Q0002000100064Q0016000100010004F53Q001600012Q006701025Q0012E7000200083Q00122Q000200023Q00122Q000300096Q000400016Q0002000400012Q005B3Q00017Q00033Q00030F3Q00687562422Q6F74737472612Q706564030B3Q00736F6674436C65616E7570030D3Q006C61756E63684D61786948756200084Q00297Q00124Q00013Q00124Q00028Q0001000100124Q00038Q00019Q008Q00017Q00043Q0003053Q007063612Q6C030D3Q006C61756E63684D61786948756203043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012C73Q00013Q0012C7000100024Q0005012Q00020001000637012Q0009000100010004F53Q000900010012C7000200033Q001254000300044Q0041000400014Q005F0002000400012Q005B3Q00017Q00", GetFEnv(), ...);