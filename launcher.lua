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
				if (Enum <= 31) then
					if (Enum <= 15) then
						if (Enum <= 7) then
							if (Enum <= 3) then
								if (Enum <= 1) then
									if (Enum > 0) then
										local B = Stk[Inst[4]];
										if not B then
											VIP = VIP + 1;
										else
											Stk[Inst[2]] = B;
											VIP = Inst[3];
										end
									else
										Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									end
								elseif (Enum > 2) then
									Stk[Inst[2]] = Inst[3];
								elseif not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 5) then
								if (Enum > 4) then
									local A = Inst[2];
									local Results, Limit = _R(Stk[A](Stk[A + 1]));
									Top = (Limit + A) - 1;
									local Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								else
									local A = Inst[2];
									Stk[A] = Stk[A]();
								end
							elseif (Enum > 6) then
								local A = Inst[2];
								do
									return Unpack(Stk, A, A + Inst[3]);
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 11) then
							if (Enum <= 9) then
								if (Enum == 8) then
									if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									Env[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum > 10) then
								local A = Inst[2];
								local Results = {Stk[A](Stk[A + 1])};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						elseif (Enum <= 13) then
							if (Enum > 12) then
								local A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
							else
								local A = Inst[2];
								local T = Stk[A];
								for Idx = A + 1, Inst[3] do
									Insert(T, Stk[Idx]);
								end
							end
						elseif (Enum == 14) then
							local A = Inst[2];
							local Results, Limit = _R(Stk[A]());
							Top = (Limit + A) - 1;
							local Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						else
							local B = Stk[Inst[4]];
							if B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 23) then
						if (Enum <= 19) then
							if (Enum <= 17) then
								if (Enum > 16) then
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
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
							elseif (Enum == 18) then
								local A = Inst[2];
								local T = Stk[A];
								local B = Inst[3];
								for Idx = 1, B do
									T[Idx] = Stk[A + Idx];
								end
							else
								local Edx;
								local Limit;
								local Results;
								local A;
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
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
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
								Stk[A] = Stk[A](Stk[A + 1]);
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
						elseif (Enum <= 21) then
							if (Enum > 20) then
								local B = Inst[3];
								local K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
							else
								Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
							end
						elseif (Enum > 22) then
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							Stk[Inst[2]] = Env[Inst[3]];
						end
					elseif (Enum <= 27) then
						if (Enum <= 25) then
							if (Enum > 24) then
								local B;
								local T;
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
								A = Inst[2];
								T = Stk[A];
								B = Inst[3];
								for Idx = 1, B do
									T[Idx] = Stk[A + Idx];
								end
							else
								local A;
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A]();
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
						elseif (Enum > 26) then
							local B;
							local A;
							Stk[Inst[2]] = Env[Inst[3]];
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
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
							Stk[Inst[2]] = Upvalues[Inst[3]];
						end
					elseif (Enum <= 29) then
						if (Enum == 28) then
							Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
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
					elseif (Enum == 30) then
						local A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Top));
					else
						local A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
					end
				elseif (Enum <= 47) then
					if (Enum <= 39) then
						if (Enum <= 35) then
							if (Enum <= 33) then
								if (Enum > 32) then
									do
										return Stk[Inst[2]];
									end
								else
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								end
							elseif (Enum == 34) then
								local A = Inst[2];
								Stk[A](Stk[A + 1]);
							else
								local A = Inst[2];
								do
									return Stk[A], Stk[A + 1];
								end
							end
						elseif (Enum <= 37) then
							if (Enum > 36) then
								VIP = Inst[3];
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
						elseif (Enum == 38) then
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
							local A = Inst[2];
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
						end
					elseif (Enum <= 43) then
						if (Enum <= 41) then
							if (Enum > 40) then
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
								Stk[Inst[2]] = {};
							end
						elseif (Enum > 42) then
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
							Stk[Inst[2]] = Inst[3] ~= 0;
						end
					elseif (Enum <= 45) then
						if (Enum > 44) then
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						else
							Stk[Inst[2]]();
						end
					elseif (Enum > 46) then
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
						if not Stk[Inst[2]] then
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
						Stk[A](Stk[A + 1]);
					end
				elseif (Enum <= 55) then
					if (Enum <= 51) then
						if (Enum <= 49) then
							if (Enum > 48) then
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
									if (Mvm[1] == 61) then
										Indexes[Idx - 1] = {Stk,Mvm[3]};
									else
										Indexes[Idx - 1] = {Upvalues,Mvm[3]};
									end
									Lupvals[#Lupvals + 1] = Indexes;
								end
								Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
							else
								local Edx;
								local Results, Limit;
								local A;
								Stk[Inst[2]] = Env[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
								Stk[A](Unpack(Stk, A + 1, Top));
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							end
						elseif (Enum == 50) then
							Stk[Inst[2]][Inst[3]] = Inst[4];
						else
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Top));
							end
						end
					elseif (Enum <= 53) then
						if (Enum > 52) then
							if (Stk[Inst[2]] == Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
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
						end
					elseif (Enum > 54) then
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
						Stk[Inst[2]] = {};
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
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
				elseif (Enum <= 59) then
					if (Enum <= 57) then
						if (Enum == 56) then
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
							Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]][Inst[3]] = Inst[4];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							do
								return;
							end
						end
					elseif (Enum > 58) then
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
					elseif (Stk[Inst[2]] ~= Inst[4]) then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 61) then
					if (Enum == 60) then
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
						Stk[Inst[2]] = Stk[Inst[3]];
					end
				elseif (Enum == 62) then
					local A = Inst[2];
					do
						return Unpack(Stk, A, Top);
					end
				else
					for Idx = Inst[2], Inst[3] do
						Stk[Idx] = nil;
					end
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!0F3Q0003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F313238313235302Q363335342Q3739373537362F2D674B4C57477030426D2D77706E492D4F656C6B354166504777745154676B2Q695342674A764E6250555044384F6E2D516250394D4F4944364E556E4E4764635F39713003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D68030E3Q004D4158494855425F4B45595F563203153Q00682Q7470733A2Q2F742E6D652F4D4158495F48554203073Q004D617869487562031A3Q006D6178692D6875622F6D6178692D6875622D636F72652E6C756103113Q006D6178692D6875622D636F72652E6C756103193Q006D6178692D6875622F6D6178692D6875622D6B65792E6C756103103Q006D6178692D6875622D6B65792E6C756103123Q007265616452656A6F696E4175746F4C6F616403123Q00726567697374657252656A6F696E482Q6F6B03153Q004D617869487562526567697374657252656A6F696E03053Q007063612Q6C03043Q007761726E03233Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0BAD0BBD18ED187D0B03A00393Q0012373Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300043Q00122Q000400056Q000500023Q00122Q000600063Q00122Q000700076Q0005000200012Q0028000600023Q001203000700083Q001203000800094Q001200060002000100021C00075Q00063100080001000100012Q003D3Q00043Q00063100090002000100012Q003D3Q00083Q000631000A0003000100032Q003D3Q00074Q003D3Q00094Q003D3Q00053Q00021C000B00043Q001209000B000A3Q00021C000B00053Q001209000B000B4Q003D000B00074Q0004000B00010002000631000C0006000100012Q003D3Q00073Q00102Q000B000C000C000631000B0007000100012Q003D3Q00063Q00021C000C00083Q000631000D0009000100012Q003D3Q000A3Q000631000E000A000100072Q003D3Q00074Q003D3Q000C4Q003D3Q000B4Q003D3Q00014Q003D3Q00034Q003D3Q00024Q003D3Q000D3Q001216000F000D4Q003D0010000E4Q000B000F00020010000602000F0035000100010004253Q003500010012160011000E3Q0012030012000F4Q003D001300104Q001F0011001300010006310011000B000100012Q003D8Q002C0011000100012Q00383Q00013Q000C3Q00043Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47000C3Q0012163Q00013Q001216000100024Q000D3Q000200020026173Q0009000100030004253Q000900010012163Q00024Q00043Q000100020006023Q000A000100010004253Q000A00010012163Q00044Q00213Q00024Q00383Q00017Q00043Q0003133Q005F4D617869487562477569526567697374727903053Q007063612Q6C0003113Q005F4D617869487562496E707574436F2Q6E01253Q00203B00013Q00010006110001001000013Q0004253Q0010000100203B00013Q00012Q001A00026Q00200001000100020006110001000F00013Q0004253Q000F0001001216000200023Q00063100033Q000100012Q003D3Q00014Q002200020002000100203B00023Q00012Q001A00035Q0020140002000300032Q003400015Q00203B00013Q00040006110001002000013Q0004253Q0020000100203B00013Q00042Q001A00026Q00200001000100020006110001001F00013Q0004253Q001F0001001216000200023Q00063100030001000100012Q003D3Q00014Q002200020002000100203B00023Q00042Q001A00035Q0020140002000300032Q003400015Q001216000100023Q00063100020002000100012Q001A8Q00220001000200012Q00383Q00013Q00033Q00043Q0003063Q00747970656F6603083Q00496E7374616E636503063Q00506172656E7403073Q0044657374726F79000D3Q0012163Q00014Q001A00016Q000D3Q000200020026173Q000C000100020004253Q000C00012Q001A7Q00203B5Q00030006113Q000C00013Q0004253Q000C00012Q001A7Q0020275Q00042Q00223Q000200012Q00383Q00017Q00013Q00030A3Q00446973636F2Q6E65637400044Q001A7Q0020275Q00012Q00223Q000200012Q00383Q00017Q00073Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C61796572030E3Q0046696E6446697273744368696C6403093Q00506C6179657247756903073Q0044657374726F7900143Q0012363Q00013Q00206Q000200122Q000200038Q0002000200202Q00013Q000400062Q0002000A000100010004253Q000A0001002027000200010005001203000400064Q000A00020004000200060F0003000F000100020004253Q000F00010020270003000200052Q001A00056Q000A0003000500020006110003001300013Q0004253Q001300010020270004000300072Q00220004000200012Q00383Q00017Q00063Q0003063Q00747970656F66030B3Q004D61786948756253746F7003083Q0066756E6374696F6E03053Q007063612Q6C03123Q005F4D617869487562436F72654C6F6164656400010D3Q001216000100013Q00203B00023Q00022Q000D00010002000200261700010008000100030004253Q00080001001216000100043Q00203B00023Q00022Q00220001000200012Q001A00016Q003D00026Q00220001000200010030323Q000500062Q00383Q00017Q00123Q0003063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503053Q00652Q726F7203313Q005B4D415849204855425D20D09DD183D0B6D0B5D0BD206578656375746F7220D181207265616466696C652F697366696C6503063Q00697061697273034Q0003453Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D636F72652E6C756120D0B220776F726B73706163652F6D6178692D6875622F030A3Q006C6F6164737472696E6703123Q00406D6178692D6875622D636F72652E6C756103193Q005B4D415849204855425D20636F6D70696C6520636F72653A2003083Q00746F737472696E6703053Q007063612Q6C03153Q005B4D415849204855425D2072756E20636F72653A2003123Q005F4D617869487562436F72654C6F616465642Q0103123Q00726567697374657252656A6F696E482Q6F6B004A4Q00189Q003Q000100024Q000100016Q00028Q00010002000100122Q000100013Q00122Q000200026Q00010002000200262Q0001000F000100030004253Q000F0001001216000100013Q001216000200044Q000D00010002000200263A00010012000100030004253Q00120001001216000100053Q001203000200064Q00220001000200012Q003F000100013Q001216000200074Q001A000300024Q000B0002000200040004253Q00210001001216000700044Q003D000800064Q000D0007000200020006110007002100013Q0004253Q00210001001216000700024Q003D000800064Q000D0007000200022Q003D000100073Q0004253Q0023000100062600020017000100020004253Q001700010006110001002700013Q0004253Q002700010026170001002A000100080004253Q002A0001001216000200053Q001203000300094Q00220002000200010012160002000A4Q003D000300013Q0012030004000B4Q002D00020004000300060200020037000100010004253Q00370001001216000400053Q0012290005000C3Q00122Q0006000D6Q000700036Q0006000200024Q0005000500064Q0004000200010012160004000E4Q003D000500024Q000B00040002000500060200040043000100010004253Q00430001001216000600053Q0012290007000F3Q00122Q0008000D6Q000900056Q0008000200024Q0007000700084Q0006000200010030323Q00100011001224000600126Q00078Q0006000200014Q000600016Q000600028Q00017Q00083Q0003063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503143Q006D6178692D6875622D636F6E6669672E6A736F6E03053Q007063612Q6C03053Q007461626C65030E3Q0052656A6F696E4175746F4C6F616400253Q0012163Q00013Q001216000100024Q000D3Q000200020026173Q000A000100030004253Q000A00010012163Q00013Q001216000100044Q000D3Q0002000200263A3Q000C000100030004253Q000C00012Q002A8Q00213Q00023Q0012163Q00023Q001203000100054Q000D3Q000200020006023Q0013000100010004253Q001300012Q002A8Q00213Q00023Q0012163Q00063Q00021C00016Q000B3Q000200010006113Q002200013Q0004253Q00220001001216000200014Q003D000300014Q000D00020002000200261700020022000100070004253Q0022000100203B0002000100080006110002002200013Q0004253Q002200012Q002A000200014Q0021000200024Q002A00026Q0021000200024Q00383Q00013Q00013Q00063Q0003043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C6503143Q006D6178692D6875622D636F6E6669672E6A736F6E000B3Q00123C3Q00013Q00206Q000200122Q000200038Q0002000200206Q000400122Q000200053Q00122Q000300066Q000200039Q009Q008Q00017Q00083Q0003063Q00747970656F6603113Q0071756575655F6F6E5F74656C65706F727403083Q0066756E6374696F6E03123Q007265616452656A6F696E4175746F4C6F616403143Q005F4D61786948756252656A6F696E51756575656400032F3Q006C6F6164737472696E67287265616466696C6528226D6178692D6875622F6C61756E636865722E6C7561222Q2928293Q01163Q001216000100013Q001216000200024Q000D00010002000200263A00010006000100030004253Q000600012Q00383Q00013Q001216000100044Q00040001000100020006020001000C000100010004253Q000C00010030323Q000500062Q00383Q00013Q00203B00013Q00050006110001001000013Q0004253Q001000012Q00383Q00013Q001203000100073Q001239000200026Q000300016Q00020002000100304Q000500086Q00017Q00013Q0003123Q00726567697374657252656A6F696E482Q6F6B00053Q0012303Q00016Q00018Q000100019Q0000016Q00017Q000F3Q0003063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503053Q00652Q726F7203313Q005B4D415849204855425D20D09DD183D0B6D0B5D0BD206578656375746F7220D181207265616466696C652F697366696C6503063Q00697061697273034Q0003443Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D6B65792E6C756120D0B220776F726B73706163652F6D6178692D6875622F030A3Q006C6F6164737472696E6703113Q00406D6178692D6875622D6B65792E6C756103183Q005B4D415849204855425D20636F6D70696C65206B65793A2003083Q00746F737472696E6703053Q007063612Q6C03143Q005B4D415849204855425D2072756E206B65793A2000403Q0012163Q00013Q001216000100024Q000D3Q000200020026173Q000A000100030004253Q000A00010012163Q00013Q001216000100044Q000D3Q0002000200263A3Q000D000100030004253Q000D00010012163Q00053Q001203000100064Q00223Q000200012Q003F7Q001216000100074Q001A00026Q000B0001000200030004253Q001C0001001216000600044Q003D000700054Q000D0006000200020006110006001C00013Q0004253Q001C0001001216000600024Q003D000700054Q000D0006000200022Q003D3Q00063Q0004253Q001E000100062600010012000100020004253Q001200010006113Q002200013Q0004253Q002200010026173Q0025000100080004253Q00250001001216000100053Q001203000200094Q00220001000200010012160001000A4Q003D00025Q0012030003000B4Q002D00010003000200060200010032000100010004253Q00320001001216000300053Q0012290004000C3Q00122Q0005000D6Q000600026Q0005000200024Q0004000400054Q0003000200010012160003000E4Q003D000400014Q000B0003000200040006020003003E000100010004253Q003E0001001216000500053Q0012290006000F3Q00122Q0007000D6Q000800046Q0007000200024Q0006000600074Q0005000200012Q0021000400024Q00383Q00017Q000D3Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C61796572477569026Q003E4003053Q00652Q726F72031B3Q005B4D415849204855425D20D09DD0B5D18220506C6179657247756900203Q00122F3Q00013Q00206Q000200122Q000200038Q0002000200122Q000100013Q00202Q0001000100044Q00010002000200062Q0001000D000100010004253Q000D0001001216000100013Q00203B0001000100050020270001000100062Q002200010002000100203B00013Q000700060200010013000100010004253Q0013000100203B00013Q00080020270001000100062Q000D0001000200020020270002000100090012030004000A3Q0012030005000B4Q000A0002000500020006020002001C000100010004253Q001C00010012160003000C3Q0012030004000D4Q00220003000200012Q003D000300014Q003D000400024Q0023000300034Q00383Q00017Q00033Q0003053Q007063612Q6C03043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012163Q00014Q001A00016Q000B3Q000200010006023Q0009000100010004253Q00090001001216000200023Q001203000300034Q003D000400014Q001F0002000400012Q00383Q00017Q000A3Q0003063Q0063726561746503073Q00776562682Q6F6B03083Q0074656C656772616D03063Q0073656372657403063Q00706C6179657203093Q00706C6179657247756903093Q006F6E4772616E746564030E3Q004D6178694875624B65794761746503093Q00686173412Q63652Q7303083Q0073686F7747617465001E4Q00139Q003Q000100024Q000100016Q0001000100024Q000300026Q00030001000200202Q0004000300014Q00053Q00064Q000600033Q00102Q0005000200064Q000600043Q00102Q0005000300064Q000600053Q00102Q00050004000600102Q00050005000100102Q0005000600024Q000600063Q00102Q0005000700064Q00040002000200104Q0008000400202Q0005000400094Q00050001000200062Q0005001B00013Q0004253Q001B00012Q001A000500064Q002C0005000100010004253Q001D000100203B00050004000A2Q002C0005000100012Q00383Q00017Q00243Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303103Q0055736572496E70757453657276696365030B3Q00482Q747053657276696365030B3Q004C6F63616C506C61796572030B3Q00476574506C6174666F726D03043Q00456E756D03083Q00506C6174666F726D03073Q00416E64726F69642Q033Q00494F5303073Q00414E44524F494403023Q00504303063Q00656D6265647303053Q007469746C6503233Q00D090D0BAD182D0B8D0B2D0B8D180D0BED0B2D0B0D0BD20D181D0BAD180D0B8D0BFD18203053Q00636F6C6F72024Q006069F84003063Q006669656C647303043Q006E616D65030B3Q00446973706C61794E616D6503053Q0076616C756503063Q00696E6C696E652Q0103043Q004E616D6503023Q00494403083Q00746F737472696E6703063Q0055736572496403053Q006A6F62496403053Q004A6F624964010003083Q004578656375746F7203123Q00D09FD0BBD0B0D182D184D0BED180D0BCD0B003063Q00662Q6F74657203043Q007465787403083Q004D4158492048554200513Q00021C7Q001206000100013Q00202Q00010001000200122Q000300036Q00010003000200122Q000200013Q00202Q00020002000200122Q000400046Q00020004000200122Q000300013Q00202Q00030003000200122Q000500056Q00030005000200202Q00040001000600202Q0005000200074Q00050002000200122Q000600083Q00202Q00060006000900202Q00060006000A00062Q0005001A000100060004253Q001A0001001216000600083Q00203B00060006000900203B00060006000B0006350005001D000100060004253Q001D00010012030006000C3Q0006020006001E000100010004253Q001E00010012030006000D3Q00021C000700014Q001900088Q00098Q000A3Q00014Q000B00016Q000C3Q000400302Q000C000F001000302Q000C001100124Q000D00066Q000E3Q000300302Q000E0014001500202Q000F0004001500102Q000E0016000F00302Q000E001700184Q000F3Q000300302Q000F0014001900202Q00100004001900102Q000F0016001000302Q000F001700184Q00103Q000300302Q00100014001A00122Q0011001B3Q00202Q00120004001C4Q00110002000200102Q00100016001100302Q0010001700184Q00113Q000300302Q00110014001D00122Q001200013Q00202Q00120012001E00102Q00110016001200302Q00110017001F4Q00123Q000300302Q0012001400204Q001300076Q00130001000200102Q00120016001300302Q0012001700184Q00133Q000300302Q00130014002100102Q00130016000600302Q0013001700184Q000D0006000100102Q000C0013000D2Q0028000D3Q0001003032000D0023002400102Q000C0022000D2Q0012000B0001000100102Q000A000E000B2Q001F0008000A00012Q00383Q00013Q00023Q00053Q00034Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E03053Q007063612Q6C02113Q0006113Q000400013Q0004253Q000400010026173Q0005000100010004253Q000500012Q00383Q00013Q001216000200023Q001216000300034Q000D00020002000200263A0002000B000100040004253Q000B00012Q00383Q00013Q001216000200053Q00063100033Q000100022Q003D8Q003D3Q00014Q00220002000200012Q00383Q00013Q00013Q000A3Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465000F3Q00121B3Q00016Q00013Q00044Q00025Q00102Q00010002000200302Q0001000300044Q00023Q000100302Q00020006000700102Q00010005000200122Q000200093Q00202Q00020002000A4Q000400016Q00020004000200102Q0001000800026Q000200016Q00017Q000B3Q0003053Q007063612Q6C03103Q006964656E746966796578656375746F722Q033Q0073796E03073Q007265717565737403093Q0053796E617073652058030B3Q004B524E4C5F4C4F4144454403043Q004B726E6C030E3Q00666C757875735F636F6E7465787403063Q00466C75787573030F3Q006765746578656375746F726E616D6503073Q00556E6B6E6F776E002A3Q0012163Q00013Q001216000100024Q000B3Q000200010006113Q000800013Q0004253Q000800010006110001000800013Q0004253Q000800012Q0021000100023Q001216000200033Q0006110002001100013Q0004253Q00110001001216000200033Q00203B0002000200040006110002001100013Q0004253Q00110001001203000200054Q0021000200023Q001216000200063Q0006110002001600013Q0004253Q00160001001203000200074Q0021000200023Q001216000200083Q0006110002001B00013Q0004253Q001B0001001203000200094Q0021000200023Q0012160002000A3Q0006110002002700013Q0004253Q00270001001216000200013Q0012160003000A4Q000B0002000200030006110002002500013Q0004253Q0025000100060100040026000100030004253Q002600010012030004000B4Q0021000400023Q0012030002000B4Q0021000200024Q00383Q00017Q00", GetFEnv(), ...);