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
				if (Enum <= 37) then
					if (Enum <= 18) then
						if (Enum <= 8) then
							if (Enum <= 3) then
								if (Enum <= 1) then
									if (Enum > 0) then
										Stk[Inst[2]] = Inst[3] ~= 0;
									else
										Stk[Inst[2]] = Inst[3] ~= 0;
										VIP = VIP + 1;
									end
								elseif (Enum == 2) then
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
								elseif (Stk[Inst[2]] ~= Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 5) then
								if (Enum == 4) then
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
									Stk[Inst[2]] = Stk[Inst[3]];
								end
							elseif (Enum <= 6) then
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 7) then
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
							end
						elseif (Enum <= 13) then
							if (Enum <= 10) then
								if (Enum == 9) then
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
									Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
								end
							elseif (Enum <= 11) then
								do
									return Stk[Inst[2]];
								end
							elseif (Enum > 12) then
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
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							end
						elseif (Enum <= 15) then
							if (Enum > 14) then
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
							end
						elseif (Enum <= 16) then
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
						elseif (Enum > 17) then
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
					elseif (Enum <= 27) then
						if (Enum <= 22) then
							if (Enum <= 20) then
								if (Enum > 19) then
									local A = Inst[2];
									do
										return Unpack(Stk, A, Top);
									end
								elseif (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 21) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
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
						elseif (Enum <= 24) then
							if (Enum > 23) then
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
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							end
						elseif (Enum <= 25) then
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
						elseif (Enum > 26) then
							local A = Inst[2];
							local Results, Limit = _R(Stk[A](Stk[A + 1]));
							Top = (Limit + A) - 1;
							local Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
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
						end
					elseif (Enum <= 32) then
						if (Enum <= 29) then
							if (Enum == 28) then
								VIP = Inst[3];
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
						elseif (Enum > 31) then
							for Idx = Inst[2], Inst[3] do
								Stk[Idx] = nil;
							end
						else
							local A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Top));
						end
					elseif (Enum <= 34) then
						if (Enum == 33) then
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
							local A = Inst[2];
							local Results = {Stk[A](Stk[A + 1])};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum <= 35) then
						local A = Inst[2];
						Stk[A] = Stk[A]();
					elseif (Enum == 36) then
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
					else
						Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
					end
				elseif (Enum <= 56) then
					if (Enum <= 46) then
						if (Enum <= 41) then
							if (Enum <= 39) then
								if (Enum > 38) then
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
									Stk[Inst[2]] = {};
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
									VIP = VIP + 1;
									Inst = Instr[VIP];
									Stk[Inst[2]] = Inst[3];
								end
							elseif (Enum == 40) then
								local A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
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
								local B = Stk[Inst[4]];
								if B then
									VIP = VIP + 1;
								else
									Stk[Inst[2]] = B;
									VIP = Inst[3];
								end
							end
						elseif (Enum <= 44) then
							Stk[Inst[2]] = Inst[3];
						elseif (Enum == 45) then
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
								if (Mvm[1] == 5) then
									Indexes[Idx - 1] = {Stk,Mvm[3]};
								else
									Indexes[Idx - 1] = {Upvalues,Mvm[3]};
								end
								Lupvals[#Lupvals + 1] = Indexes;
							end
							Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
						end
					elseif (Enum <= 51) then
						if (Enum <= 48) then
							if (Enum > 47) then
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
								local A = Inst[2];
								Stk[A](Stk[A + 1]);
							end
						elseif (Enum <= 49) then
							local A = Inst[2];
							do
								return Stk[A], Stk[A + 1];
							end
						elseif (Enum == 50) then
							Env[Inst[3]] = Stk[Inst[2]];
						else
							local B = Stk[Inst[4]];
							if not B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 53) then
						if (Enum == 52) then
							do
								return;
							end
						else
							local A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						end
					elseif (Enum <= 54) then
						local A = Inst[2];
						local T = Stk[A];
						for Idx = A + 1, Inst[3] do
							Insert(T, Stk[Idx]);
						end
					elseif (Enum > 55) then
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
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
					end
				elseif (Enum <= 65) then
					if (Enum <= 60) then
						if (Enum <= 58) then
							if (Enum == 57) then
								local A = Inst[2];
								local Results = {Stk[A]()};
								local Limit = Inst[4];
								local Edx = 0;
								for Idx = A, Limit do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								local A = Inst[2];
								local T = Stk[A];
								local B = Inst[3];
								for Idx = 1, B do
									T[Idx] = Stk[A + Idx];
								end
							end
						elseif (Enum == 59) then
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
						else
							local A = Inst[2];
							do
								return Unpack(Stk, A, A + Inst[3]);
							end
						end
					elseif (Enum <= 62) then
						if (Enum == 61) then
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
					elseif (Enum <= 63) then
						Stk[Inst[2]][Inst[3]] = Inst[4];
					elseif (Enum > 64) then
						Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
					else
						Stk[Inst[2]]();
					end
				elseif (Enum <= 70) then
					if (Enum <= 67) then
						if (Enum == 66) then
							local B = Inst[3];
							local K = Stk[B];
							for Idx = B + 1, Inst[4] do
								K = K .. Stk[Idx];
							end
							Stk[Inst[2]] = K;
						else
							Stk[Inst[2]] = Env[Inst[3]];
						end
					elseif (Enum <= 68) then
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
					elseif (Enum > 69) then
						local A = Inst[2];
						local Results, Limit = _R(Stk[A]());
						Top = (Limit + A) - 1;
						local Edx = 0;
						for Idx = A, Top do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					else
						Stk[Inst[2]] = Upvalues[Inst[3]];
					end
				elseif (Enum <= 72) then
					if (Enum == 71) then
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
				elseif (Enum <= 73) then
					if Stk[Inst[2]] then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				elseif (Enum == 74) then
					local A = Inst[2];
					local B = Stk[Inst[3]];
					Stk[A + 1] = B;
					Stk[A] = B[Inst[4]];
				else
					local A = Inst[2];
					Stk[A](Unpack(Stk, A + 1, Inst[3]));
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!113Q0003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F313238313235302Q363335342Q3739373537362F2D674B4C57477030426D2D77706E492D4F656C6B354166504777745154676B2Q695342674A764E6250555044384F6E2D516250394D4F4944364E556E4E4764635F39713003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D68030E3Q004D4158494855425F4B45595F563203153Q00682Q7470733A2Q2F742E6D652F4D4158495F485542033C3Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F6B6F744D613073316E2F6D6178692D6875622F6D61737465722F03363Q00682Q7470733A2Q2F63646E2E6A7364656C6976722E6E65742F67682F6B6F744D613073316E2F6D6178692D687562406D61737465722F03073Q004D617869487562031A3Q006D6178692D6875622F6D6178692D6875622D636F72652E6C756103113Q006D6178692D6875622D636F72652E6C756103193Q006D6178692D6875622F6D6178692D6875622D6B65792E6C756103103Q006D6178692D6875622D6B65792E6C756103123Q007265616452656A6F696E4175746F4C6F616403123Q00726567697374657252656A6F696E482Q6F6B03153Q004D617869487562526567697374657252656A6F696E03053Q007063612Q6C03043Q007761726E03233Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0BAD0BBD18ED187D0B03A004A3Q0012263Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300043Q00122Q000400053Q00122Q000500063Q00122Q000600076Q000700023Q00122Q000800083Q00122Q000900094Q003A0007000200012Q0011000800023Q00122C0009000A3Q00122C000A000B4Q003A00080002000100020A00095Q00062E000A0001000100022Q00053Q00094Q00053Q00043Q00020A000B00023Q00020A000C00033Q00020A000D00043Q00062E000E0005000100062Q00053Q000D4Q00053Q00094Q00053Q000A4Q00053Q00054Q00053Q000B4Q00053Q000C3Q00062E000F0006000100012Q00053Q00063Q00062E00100007000100012Q00053Q000F3Q00062E00110008000100042Q00053Q00094Q00053Q00104Q00053Q000E4Q00053Q00073Q00020A001200093Q0012320012000C3Q00020A0012000A3Q0012320012000D4Q0005001200094Q002300120001000200062E0013000B000100012Q00053Q00093Q0010370012000E001300062E0012000C000100022Q00053Q000E4Q00053Q00083Q00020A0013000D3Q00062E0014000E000100012Q00053Q00113Q00062E0015000F000100072Q00053Q00094Q00053Q00134Q00053Q00124Q00053Q00014Q00053Q00034Q00053Q00024Q00053Q00143Q0012430016000F4Q0005001700154Q0022001600020017000647001600460001000100041C3Q00460001001243001800103Q00122C001900114Q0005001A00174Q004B0018001A000100062E00180010000100012Q00058Q00400018000100012Q00343Q00013Q00113Q00043Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47000C3Q0012433Q00013Q001243000100024Q00283Q000200020026063Q00090001000300041C3Q000900010012433Q00024Q00233Q000100020006473Q000A0001000100041C3Q000A00010012433Q00044Q000B3Q00024Q00343Q00017Q00013Q0003123Q004D6178694875624F2Q66696369616C52617700084Q00458Q00233Q0001000200201700013Q0001000647000100060001000100041C3Q000600012Q0045000100014Q000B000100024Q00343Q00017Q000A3Q0003063Q00747970656F6603023Q006F7303053Q007461626C6503043Q0074696D65028Q0003043Q006D61746803063Q0072616E646F6D025Q00408F40024Q008087C34003083Q00746F737472696E6700293Q0012433Q00013Q001243000100024Q00283Q000200020026063Q000E0001000300041C3Q000E00010012433Q00023Q0020175Q00040006493Q000E00013Q00041C3Q000E00010012433Q00023Q0020175Q00042Q00233Q000100020006473Q000F0001000100041C3Q000F000100122C3Q00053Q001243000100013Q001243000200064Q00280001000200020026060001001F0001000300041C3Q001F0001001243000100063Q0020170001000100070006490001001F00013Q00041C3Q001F0001001243000100063Q00201D00010001000700122Q000200083Q00122Q000300096Q00010003000200062Q000100200001000100041C3Q0020000100122C000100053Q0012430002000A4Q001A00038Q00020002000200122Q0003000A6Q000400016Q0003000200024Q0002000200034Q000200028Q00017Q000B3Q0003063Q00747970656F6603043Q0067616D6503073Q00482Q747047657403083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503063Q00737472696E67034Q0003073Q007265717565737403053Q007461626C6503043Q00426F647901443Q001207000100013Q00122Q000200023Q00202Q0002000200034Q00010002000200262Q000100270001000400041C3Q00270001001243000100053Q001224000200023Q00202Q0002000200034Q00038Q000400016Q00010004000200062Q0001001600013Q00041C3Q00160001001243000300064Q0005000400024Q0028000300020002002606000300160001000700041C3Q00160001002613000200160001000800041C3Q001600012Q000B000200023Q001243000300053Q001229000400023Q00202Q0004000400034Q00058Q0003000500044Q000200046Q000100033Q00062Q0001002700013Q00041C3Q00270001001243000300064Q0005000400024Q0028000300020002002606000300270001000700041C3Q00270001002613000200270001000800041C3Q002700012Q000B000200023Q001243000100013Q001243000200094Q0028000100020002002606000100410001000400041C3Q00410001001243000100053Q00062E00023Q000100012Q00058Q00220001000200020006490001004100013Q00041C3Q00410001001243000300064Q0005000400024Q0028000300020002002606000300410001000A00041C3Q00410001001243000300063Q00201700040002000B2Q0028000300020002002606000300410001000700041C3Q0041000100201700030002000B002613000300410001000800041C3Q0041000100201700030002000B2Q000B000300024Q0020000100014Q000B000100024Q00343Q00013Q00013Q00043Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F642Q033Q0047455400083Q00123B3Q00016Q00013Q00024Q00025Q00102Q00010002000200302Q0001000300046Q00019Q008Q00017Q00063Q0003043Q007479706503063Q00737472696E67034Q00030A3Q006C6F6164737472696E6703073Q00406D6F64756C650002153Q001243000200014Q000500036Q0028000200020002002606000200070001000200041C3Q000700010026063Q00090001000300041C3Q000900012Q000100026Q000B000200023Q001243000200044Q000500035Q0006330004000E0001000100041C3Q000E000100122C000400054Q0035000200040002002606000200120001000600041C3Q001200014Q00026Q0001000200014Q000B000200024Q00343Q00017Q000B3Q0003063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503063Q0069706169727303013Q0040030F3Q004D6178694875625265706F4F6E6C792Q012Q033Q003F763D03053Q00652Q726F7203393Q005B4D415849204855425D20D0A2D0BED0BBD18CD0BAD0BE20D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD18BD0B920D180D0B5D0BFD0BE3A20024F3Q001243000200013Q001243000300024Q0028000200020002002606000200210001000300041C3Q00210001001243000200013Q001243000300044Q0028000200020002002606000200210001000300041C3Q00210001001243000200054Q0005000300014Q002200020002000400041C3Q001F0001001243000700044Q0005000800064Q00280007000200020006490007001F00013Q00041C3Q001F0001001243000700024Q0002000800066Q0007000200024Q00088Q000900073Q00122Q000A00066Q000B00066Q000A000A000B4Q0008000A000200062Q0008001F00013Q00041C3Q001F00012Q000B000700023Q00061E0002000E0001000200041C3Q000E00012Q0045000200014Q0023000200010002002017000300020007002613000300270001000800041C3Q002700014Q00036Q0001000300014Q003E000400026Q000500026Q0005000100024Q000600036Q0004000200012Q0045000500044Q003D00050001000200122Q000600056Q000700046Q00060002000800044Q004300012Q0045000B00054Q0030000C000A6Q000D5Q00122Q000E00096Q000F00056Q000C000C000F4Q000B000200024Q000C8Q000D000B3Q00122Q000E00066Q000F8Q000E000E000F4Q000C000E000200062Q000C004300013Q00041C3Q004300012Q000B000B00023Q00061E000600330001000200041C3Q003300010006490003004C00013Q00041C3Q004C00010012430006000A3Q00122C0007000B4Q000500086Q00420007000700082Q002F0006000200012Q0020000600064Q000B000600024Q00343Q00017Q00043Q0003133Q005F4D617869487562477569526567697374727903053Q007063612Q6C0003113Q005F4D617869487562496E707574436F2Q6E01253Q00201700013Q00010006490001001000013Q00041C3Q0010000100201700013Q00012Q004500026Q00410001000100020006490001000F00013Q00041C3Q000F0001001243000200023Q00062E00033Q000100012Q00053Q00014Q002F00020002000100201700023Q00012Q004500035Q0020250002000300032Q003800015Q00201700013Q00040006490001002000013Q00041C3Q0020000100201700013Q00042Q004500026Q00410001000100020006490001001F00013Q00041C3Q001F0001001243000200023Q00062E00030001000100012Q00053Q00014Q002F00020002000100201700023Q00042Q004500035Q0020250002000300032Q003800015Q001243000100023Q00062E00020002000100012Q00458Q002F0001000200012Q00343Q00013Q00033Q00043Q0003063Q00747970656F6603083Q00496E7374616E636503063Q00506172656E7403073Q0044657374726F79000D3Q0012433Q00014Q004500016Q00283Q000200020026063Q000C0001000200041C3Q000C00012Q00457Q0020175Q00030006493Q000C00013Q00041C3Q000C00012Q00457Q00204A5Q00042Q002F3Q000200012Q00343Q00017Q00013Q00030A3Q00446973636F2Q6E65637400044Q00457Q00204A5Q00012Q002F3Q000200012Q00343Q00017Q00073Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C61796572030E3Q0046696E6446697273744368696C6403093Q00506C6179657247756903073Q0044657374726F7900143Q0012483Q00013Q00206Q000200122Q000200038Q0002000200202Q00013Q000400062Q0002000A0001000100041C3Q000A000100204A00020001000500122C000400064Q003500020004000200062A0003000F0001000200041C3Q000F000100204A0003000200052Q004500056Q00350003000500020006490003001300013Q00041C3Q0013000100204A0004000300072Q002F0004000200012Q00343Q00017Q00063Q0003063Q00747970656F66030B3Q004D61786948756253746F7003083Q0066756E6374696F6E03053Q007063612Q6C03123Q005F4D617869487562436F72654C6F6164656400010D3Q001243000100013Q00201700023Q00022Q0028000100020002002606000100080001000300041C3Q00080001001243000100043Q00201700023Q00022Q002F0001000200012Q004500016Q000500026Q002F00010002000100303F3Q000500062Q00343Q00017Q000D3Q0003113Q006D6178692D6875622D636F72652E6C7561034Q0003053Q00652Q726F7203483Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D636F72652E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703123Q00406D6178692D6875622D636F72652E6C756103193Q005B4D415849204855425D20636F6D70696C6520636F72653A2003083Q00746F737472696E6703053Q007063612Q6C03153Q005B4D415849204855425D2072756E20636F72653A2003123Q005F4D617869487562436F72654C6F616465642Q0103123Q00726567697374657252656A6F696E482Q6F6B00304Q000E9Q003Q000100024Q000100016Q00028Q0001000200014Q000100023Q00122Q000200016Q000300036Q00010003000200062Q0001000D00013Q00041C3Q000D0001002606000100100001000200041C3Q00100001001243000200033Q00122C000300044Q002F000200020001001243000200054Q0005000300013Q00122C000400064Q00160002000400030006470002001D0001000100041C3Q001D0001001243000400033Q002Q12000500073Q00122Q000600086Q000700036Q0006000200024Q0005000500064Q000400020001001243000400094Q0005000500024Q0022000400020005000647000400290001000100041C3Q00290001001243000600033Q002Q120007000A3Q00122Q000800086Q000900056Q0008000200024Q0007000700084Q00060002000100303F3Q000B000C0012270006000D6Q00078Q0006000200014Q000600016Q000600028Q00017Q00083Q0003063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503143Q006D6178692D6875622D636F6E6669672E6A736F6E03053Q007063612Q6C03053Q007461626C65030E3Q0052656A6F696E4175746F4C6F616400253Q0012433Q00013Q001243000100024Q00283Q000200020026063Q000A0001000300041C3Q000A00010012433Q00013Q001243000100044Q00283Q000200020026133Q000C0001000300041C3Q000C00012Q00018Q000B3Q00023Q0012433Q00023Q00122C000100054Q00283Q000200020006473Q00130001000100041C3Q001300012Q00018Q000B3Q00023Q0012433Q00063Q00020A00016Q00223Q000200010006493Q002200013Q00041C3Q00220001001243000200014Q0005000300014Q0028000200020002002606000200220001000700041C3Q002200010020170002000100080006490002002200013Q00041C3Q002200012Q0001000200014Q000B000200024Q000100026Q000B000200024Q00343Q00013Q00013Q00063Q0003043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C6503143Q006D6178692D6875622D636F6E6669672E6A736F6E000B3Q0012183Q00013Q00206Q000200122Q000200038Q0002000200206Q000400122Q000200053Q00122Q000300066Q000200039Q009Q008Q00017Q000E3Q0003063Q00747970656F6603113Q0071756575655F6F6E5F74656C65706F727403083Q0066756E6374696F6E03123Q007265616452656A6F696E4175746F4C6F616403143Q005F4D61786948756252656A6F696E5175657565640003103Q004D6178694875624C6F6164657255726C034Q0003193Q006C6F6164737472696E672867616D653A482Q7470476574282203053Q00222Q29282903123Q004D6178694875624F2Q66696369616C526177030F3Q006C6F616465722E6C7561222Q292829032F3Q006C6F6164737472696E67287265616466696C6528226D6178692D6875622F6C61756E636865722E6C7561222Q2928293Q012A3Q001243000100013Q001243000200024Q0028000100020002002613000100060001000300041C3Q000600012Q00343Q00013Q001243000100044Q00230001000100020006470001000C0001000100041C3Q000C000100303F3Q000500062Q00343Q00013Q00201700013Q00050006490001001000013Q00041C3Q001000012Q00343Q00014Q0020000100013Q00201700023Q00070006490002001C00013Q00041C3Q001C000100201700023Q00070026130002001C0001000800041C3Q001C000100122C000200093Q00201700033Q000700122C0004000A4Q004200010002000400041C3Q0025000100201700023Q000B0006490002002400013Q00041C3Q0024000100122C000200093Q00201700033Q000B00122C0004000C4Q004200010002000400041C3Q0025000100122C0001000D3Q001243000200024Q0005000300014Q002F00020002000100303F3Q0005000E2Q00343Q00017Q00013Q0003123Q00726567697374657252656A6F696E482Q6F6B00053Q00122D3Q00016Q00018Q000100019Q0000016Q00017Q000A3Q0003103Q006D6178692D6875622D6B65792E6C7561034Q0003053Q00652Q726F7203473Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D6B65792E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703113Q00406D6178692D6875622D6B65792E6C756103183Q005B4D415849204855425D20636F6D70696C65206B65793A2003083Q00746F737472696E6703053Q007063612Q6C03143Q005B4D415849204855425D2072756E206B65793A2000264Q00097Q00122Q000100016Q000200018Q0002000200064Q000800013Q00041C3Q000800010026063Q000B0001000200041C3Q000B0001001243000100033Q00122C000200044Q002F000100020001001243000100054Q000500025Q00122C000300064Q0016000100030002000647000100180001000100041C3Q00180001001243000300033Q002Q12000400073Q00122Q000500086Q000600026Q0005000200024Q0004000400054Q000300020001001243000300094Q0005000400014Q0022000300020004000647000300240001000100041C3Q00240001001243000500033Q002Q120006000A3Q00122Q000700086Q000800046Q0007000200024Q0006000600074Q0005000200012Q000B000400024Q00343Q00017Q000D3Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C61796572477569026Q003E4003053Q00652Q726F72031B3Q005B4D415849204855425D20D09DD0B5D18220506C6179657247756900203Q00122B3Q00013Q00206Q000200122Q000200038Q0002000200122Q000100013Q00202Q0001000100044Q00010002000200062Q0001000D0001000100041C3Q000D0001001243000100013Q00201700010001000500204A0001000100062Q002F00010002000100201700013Q0007000647000100130001000100041C3Q0013000100201700013Q000800204A0001000100062Q002800010002000200204A00020001000900122C0004000A3Q00122C0005000B4Q00350002000500020006470002001C0001000100041C3Q001C00010012430003000C3Q00122C0004000D4Q002F0003000200012Q0005000300014Q0005000400024Q0031000300034Q00343Q00017Q00033Q0003053Q007063612Q6C03043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012433Q00014Q004500016Q00223Q000200010006473Q00090001000100041C3Q00090001001243000200023Q00122C000300034Q0005000400014Q004B0002000400012Q00343Q00017Q000A3Q0003063Q0063726561746503073Q00776562682Q6F6B03083Q0074656C656772616D03063Q0073656372657403063Q00706C6179657203093Q00706C6179657247756903093Q006F6E4772616E746564030E3Q004D6178694875624B65794761746503093Q00686173412Q63652Q7303083Q0073686F7747617465001E4Q00449Q003Q000100024Q000100016Q0001000100024Q000300026Q00030001000200202Q0004000300014Q00053Q00064Q000600033Q00102Q0005000200064Q000600043Q00102Q0005000300064Q000600053Q00102Q00050004000600102Q00050005000100102Q0005000600024Q000600063Q00102Q0005000700064Q00040002000200104Q0008000400202Q0005000400094Q00050001000200062Q0005001B00013Q00041C3Q001B00012Q0045000500064Q004000050001000100041C3Q001D000100201700050004000A2Q00400005000100012Q00343Q00017Q00243Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303103Q0055736572496E70757453657276696365030B3Q00482Q747053657276696365030B3Q004C6F63616C506C61796572030B3Q00476574506C6174666F726D03043Q00456E756D03083Q00506C6174666F726D03073Q00416E64726F69642Q033Q00494F5303073Q00414E44524F494403023Q00504303063Q00656D6265647303053Q007469746C6503233Q00D090D0BAD182D0B8D0B2D0B8D180D0BED0B2D0B0D0BD20D181D0BAD180D0B8D0BFD18203053Q00636F6C6F72024Q006069F84003063Q006669656C647303043Q006E616D65030B3Q00446973706C61794E616D6503053Q0076616C756503063Q00696E6C696E652Q0103043Q004E616D6503023Q00494403083Q00746F737472696E6703063Q0055736572496403053Q006A6F62496403053Q004A6F624964010003083Q004578656375746F7203123Q00D09FD0BBD0B0D182D184D0BED180D0BCD0B003063Q00662Q6F74657203043Q007465787403083Q004D4158492048554200513Q00020A7Q001219000100013Q00202Q00010001000200122Q000300036Q00010003000200122Q000200013Q00202Q00020002000200122Q000400046Q00020004000200122Q000300013Q00202Q00030003000200122Q000500056Q00030005000200202Q00040001000600202Q0005000200074Q00050002000200122Q000600083Q00202Q00060006000900202Q00060006000A00062Q0005001A0001000600041C3Q001A0001001243000600083Q00201700060006000900201700060006000B00060F0005001D0001000600041C3Q001D000100122C0006000C3Q0006470006001E0001000100041C3Q001E000100122C0006000D3Q00020A000700014Q001000088Q00098Q000A3Q00014Q000B00016Q000C3Q000400302Q000C000F001000302Q000C001100124Q000D00066Q000E3Q000300302Q000E0014001500202Q000F0004001500102Q000E0016000F00302Q000E001700184Q000F3Q000300302Q000F0014001900202Q00100004001900102Q000F0016001000302Q000F001700184Q00103Q000300302Q00100014001A00122Q0011001B3Q00202Q00120004001C4Q00110002000200102Q00100016001100302Q0010001700184Q00113Q000300302Q00110014001D00122Q001200013Q00202Q00120012001E00102Q00110016001200302Q00110017001F4Q00123Q000300302Q0012001400204Q001300076Q00130001000200102Q00120016001300302Q0012001700184Q00133Q000300302Q00130014002100102Q00130016000600302Q0013001700184Q000D00060001001037000C0013000D2Q0011000D3Q000100303F000D00230024001037000C0022000D2Q003A000B00010001001037000A000E000B2Q004B0008000A00012Q00343Q00013Q00023Q00053Q00034Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E03053Q007063612Q6C02113Q0006493Q000400013Q00041C3Q000400010026063Q00050001000100041C3Q000500012Q00343Q00013Q001243000200023Q001243000300034Q00280002000200020026130002000B0001000400041C3Q000B00012Q00343Q00013Q001243000200053Q00062E00033Q000100022Q00058Q00053Q00014Q002F0002000200012Q00343Q00013Q00013Q000A3Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465000F3Q0012213Q00016Q00013Q00044Q00025Q00102Q00010002000200302Q0001000300044Q00023Q000100302Q00020006000700102Q00010005000200122Q000200093Q00202Q00020002000A4Q000400016Q00020004000200102Q0001000800026Q000200016Q00017Q000B3Q0003053Q007063612Q6C03103Q006964656E746966796578656375746F722Q033Q0073796E03073Q007265717565737403093Q0053796E617073652058030B3Q004B524E4C5F4C4F4144454403043Q004B726E6C030E3Q00666C757875735F636F6E7465787403063Q00466C75787573030F3Q006765746578656375746F726E616D6503073Q00556E6B6E6F776E002A3Q0012433Q00013Q001243000100024Q00223Q000200010006493Q000800013Q00041C3Q000800010006490001000800013Q00041C3Q000800012Q000B000100023Q001243000200033Q0006490002001100013Q00041C3Q00110001001243000200033Q0020170002000200040006490002001100013Q00041C3Q0011000100122C000200054Q000B000200023Q001243000200063Q0006490002001600013Q00041C3Q0016000100122C000200074Q000B000200023Q001243000200083Q0006490002001B00013Q00041C3Q001B000100122C000200094Q000B000200023Q0012430002000A3Q0006490002002700013Q00041C3Q00270001001243000200013Q0012430003000A4Q00220002000200030006490002002500013Q00041C3Q00250001000633000400260001000300041C3Q0026000100122C0004000B4Q000B000400023Q00122C0002000B4Q000B000200024Q00343Q00017Q00", GetFEnv(), ...);
