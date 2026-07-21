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
				if (Enum <= 42) then
					if (Enum <= 20) then
						if (Enum <= 9) then
							if (Enum <= 4) then
								if (Enum <= 1) then
									if (Enum > 0) then
										if Stk[Inst[2]] then
											VIP = VIP + 1;
										else
											VIP = Inst[3];
										end
									else
										Stk[Inst[2]] = {};
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
									local B = Stk[Inst[4]];
									if not B then
										VIP = VIP + 1;
									else
										Stk[Inst[2]] = B;
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
							elseif (Enum <= 6) then
								if (Enum > 5) then
									local A = Inst[2];
									local T = Stk[A];
									for Idx = A + 1, Inst[3] do
										Insert(T, Stk[Idx]);
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
							elseif (Enum <= 7) then
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
							elseif (Enum == 8) then
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
						elseif (Enum <= 14) then
							if (Enum <= 11) then
								if (Enum == 10) then
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
								elseif (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 12) then
								local A = Inst[2];
								local Results = {Stk[A]()};
								local Limit = Inst[4];
								local Edx = 0;
								for Idx = A, Limit do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							elseif (Enum > 13) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
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
						elseif (Enum <= 17) then
							if (Enum <= 15) then
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
							elseif (Enum == 16) then
								Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
							else
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							end
						elseif (Enum <= 18) then
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
						elseif (Enum == 19) then
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
							Stk[Inst[2]] = Upvalues[Inst[3]];
						end
					elseif (Enum <= 31) then
						if (Enum <= 25) then
							if (Enum <= 22) then
								if (Enum == 21) then
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
								else
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Top));
								end
							elseif (Enum <= 23) then
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
							elseif (Enum == 24) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							else
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							end
						elseif (Enum <= 28) then
							if (Enum <= 26) then
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
							elseif (Enum == 27) then
								Stk[Inst[2]][Inst[3]] = Inst[4];
							else
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
							end
						elseif (Enum <= 29) then
							local A = Inst[2];
							Stk[A] = Stk[A]();
						elseif (Enum > 30) then
							Upvalues[Inst[3]] = Stk[Inst[2]];
						else
							Stk[Inst[2]][Stk[Inst[3]]] = Inst[4];
						end
					elseif (Enum <= 36) then
						if (Enum <= 33) then
							if (Enum == 32) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								local A = Inst[2];
								do
									return Unpack(Stk, A, Top);
								end
							end
						elseif (Enum <= 34) then
							if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 35) then
							local A = Inst[2];
							local T = Stk[A];
							local B = Inst[3];
							for Idx = 1, B do
								T[Idx] = Stk[A + Idx];
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
					elseif (Enum <= 39) then
						if (Enum <= 37) then
							local A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
						elseif (Enum == 38) then
							for Idx = Inst[2], Inst[3] do
								Stk[Idx] = nil;
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
					elseif (Enum <= 40) then
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
							if (Mvm[1] == 44) then
								Indexes[Idx - 1] = {Stk,Mvm[3]};
							else
								Indexes[Idx - 1] = {Upvalues,Mvm[3]};
							end
							Lupvals[#Lupvals + 1] = Indexes;
						end
						Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
					elseif (Enum > 41) then
						VIP = Inst[3];
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
					end
				elseif (Enum <= 63) then
					if (Enum <= 52) then
						if (Enum <= 47) then
							if (Enum <= 44) then
								if (Enum == 43) then
									Stk[Inst[2]]();
								else
									Stk[Inst[2]] = Stk[Inst[3]];
								end
							elseif (Enum <= 45) then
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
							elseif (Enum == 46) then
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
							else
								local A = Inst[2];
								Stk[A](Stk[A + 1]);
							end
						elseif (Enum <= 49) then
							if (Enum > 48) then
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
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 50) then
							if (Stk[Inst[2]] == Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 51) then
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
					elseif (Enum <= 57) then
						if (Enum <= 54) then
							if (Enum == 53) then
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
								Stk[Inst[2]] = Inst[3] ~= 0;
							end
						elseif (Enum <= 55) then
							if not Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 56) then
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
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
						end
					elseif (Enum <= 60) then
						if (Enum <= 58) then
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
						elseif (Enum == 59) then
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
					elseif (Enum <= 61) then
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
					elseif (Enum > 62) then
						local A = Inst[2];
						local Results, Limit = _R(Stk[A]());
						Top = (Limit + A) - 1;
						local Edx = 0;
						for Idx = A, Top do
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
				elseif (Enum <= 74) then
					if (Enum <= 68) then
						if (Enum <= 65) then
							if (Enum > 64) then
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
								local B = Inst[3];
								local K = Stk[B];
								for Idx = B + 1, Inst[4] do
									K = K .. Stk[Idx];
								end
								Stk[Inst[2]] = K;
							end
						elseif (Enum <= 66) then
							local A = Inst[2];
							do
								return Stk[A], Stk[A + 1];
							end
						elseif (Enum > 67) then
							local B = Stk[Inst[4]];
							if B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						elseif (Stk[Inst[2]] == Inst[4]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 71) then
						if (Enum <= 69) then
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
						elseif (Enum == 70) then
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
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum <= 72) then
						local A = Inst[2];
						local B = Stk[Inst[3]];
						Stk[A + 1] = B;
						Stk[A] = B[Inst[4]];
					elseif (Enum > 73) then
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
				elseif (Enum <= 79) then
					if (Enum <= 76) then
						if (Enum == 75) then
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
					elseif (Enum <= 77) then
						local A = Inst[2];
						do
							return Unpack(Stk, A, A + Inst[3]);
						end
					elseif (Enum == 78) then
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
					else
						local A = Inst[2];
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
					end
				elseif (Enum <= 82) then
					if (Enum <= 80) then
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
					elseif (Enum > 81) then
						Stk[Inst[2]] = Inst[3];
					else
						Env[Inst[3]] = Stk[Inst[2]];
					end
				elseif (Enum <= 83) then
					Stk[Inst[2]] = Inst[3] ~= 0;
					VIP = VIP + 1;
				elseif (Enum == 84) then
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
				else
					do
						return Stk[Inst[2]];
					end
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!143Q0003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F313238313235302Q363335342Q3739373537362F2D674B4C57477030426D2D77706E492D4F656C6B354166504777745154676B2Q695342674A764E6250555044384F6E2D516250394D4F4944364E556E4E4764635F39713003793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F31342Q302Q322Q3435303539343630333038302F48573965555250525A432Q5277743462547A52412D58346A6B323056626C414C4642555F6A505A7A534C63735964453466444656635A6D5776755F784571737955584D6803153Q00682Q7470733A2Q2F742E6D652F4D4158495F48554203073Q006D61786968756203103Q004D4158492D4855422D6B65792E74787403213Q00682Q7470733A2Q2F66756E7061792E636F6D2F75736572732F363431323534332F033C3Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F6B6F744D613073316E2F6D6178692D6875622F6D61737465722F03363Q00682Q7470733A2Q2F63646E2E6A7364656C6976722E6E65742F67682F6B6F744D613073316E2F6D6178692D687562406D61737465722F03073Q004D61786948756203143Q006D6178692D6875622D636F6E6669672E6A736F6E031A3Q006D6178692D6875622F6D6178692D6875622D636F72652E6C756103113Q006D6178692D6875622D636F72652E6C756103193Q006D6178692D6875622F6D6178692D6875622D6B65792E6C756103103Q006D6178692D6875622D6B65792E6C756103123Q007265616452656A6F696E4175746F4C6F616403123Q00726567697374657252656A6F696E482Q6F6B03153Q004D617869487562526567697374657252656A6F696E03053Q007063612Q6C03043Q007761726E03233Q005B4D415849204855425D20D09ED188D0B8D0B1D0BAD0B020D0BAD0BBD18ED187D0B03A00573Q0012173Q00013Q00122Q000100023Q00122Q000200033Q00122Q000300043Q00122Q000400053Q00122Q000500063Q00122Q000600073Q00122Q000700083Q00122Q000800093Q00122Q0009000A6Q000A00023Q001252000B000B3Q001252000C000C4Q0024000A000200014Q000B00023Q001252000C000D3Q001252000D000E4Q0024000B00020001000210000C5Q000628000D0001000100022Q002C3Q000C4Q002C3Q00063Q000210000E00023Q000210000F00033Q000210001000043Q00062800110005000100062Q002C3Q000C4Q002C3Q000D4Q002C3Q00074Q002C3Q000E4Q002C3Q000F4Q002C3Q00103Q00062800120006000100012Q002C3Q00083Q00062800130007000100012Q002C3Q00123Q00062800140008000100042Q002C3Q000C4Q002C3Q00134Q002C3Q00114Q002C3Q000A3Q00062800150009000100012Q002C3Q00093Q0012510015000F3Q0006280015000A000100012Q002C3Q00093Q0006280016000B000100012Q002C3Q00093Q0002100017000C3Q001251001700104Q002C0017000C4Q001D0017000100020006280018000D000100012Q002C3Q000C3Q0010190017001100180006280017000E000100022Q002C3Q00114Q002C3Q000B3Q0002100018000F3Q00062800190010000100012Q002C3Q00143Q000628001A00110001000C2Q002C3Q000C4Q002C3Q00184Q002C3Q00174Q002C3Q00154Q002C3Q00014Q002C3Q00024Q002C3Q00034Q002C3Q00044Q002C3Q00054Q002C3Q00164Q002C3Q00134Q002C3Q00193Q001230001B00124Q002C001C001A4Q000D001B0002001C000637001B00530001000100042A3Q00530001001230001D00133Q001252001E00144Q002C001F001C4Q0038001D001F0001000628001D0012000100012Q002C8Q002B001D000100012Q00333Q00013Q00133Q00043Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47000C3Q0012303Q00013Q001230000100024Q00253Q000200020026433Q00090001000300042A3Q000900010012303Q00024Q001D3Q000100020006373Q000A0001000100042A3Q000A00010012303Q00044Q00553Q00024Q00333Q00017Q00013Q0003123Q004D6178694875624F2Q66696369616C52617700084Q00148Q001D3Q0001000200201100013Q0001000637000100060001000100042A3Q000600012Q0014000100014Q0055000100024Q00333Q00017Q000A3Q0003063Q00747970656F6603023Q006F7303053Q007461626C6503043Q0074696D65028Q0003043Q006D61746803063Q0072616E646F6D025Q00408F40024Q008087C34003083Q00746F737472696E6700293Q0012303Q00013Q001230000100024Q00253Q000200020026433Q000E0001000300042A3Q000E00010012303Q00023Q0020115Q00040006013Q000E00013Q00042A3Q000E00010012303Q00023Q0020115Q00042Q001D3Q000100020006373Q000F0001000100042A3Q000F00010012523Q00053Q001230000100013Q001230000200064Q00250001000200020026430001001F0001000300042A3Q001F0001001230000100063Q0020110001000100070006010001001F00013Q00042A3Q001F0001001230000100063Q00203B00010001000700122Q000200083Q00122Q000300096Q00010003000200062Q000100200001000100042A3Q00200001001252000100053Q0012300002000A4Q000A00038Q00020002000200122Q0003000A6Q000400016Q0003000200024Q0002000200034Q000200028Q00017Q000B3Q0003063Q00747970656F6603043Q0067616D6503073Q00482Q747047657403083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503063Q00737472696E67034Q0003073Q007265717565737403053Q007461626C6503043Q00426F647901443Q001213000100013Q00122Q000200023Q00202Q0002000200034Q00010002000200262Q000100270001000400042A3Q00270001001230000100053Q00123D000200023Q00202Q0002000200034Q00038Q000400016Q00010004000200062Q0001001600013Q00042A3Q00160001001230000300064Q002C000400024Q0025000300020002002643000300160001000700042A3Q0016000100260B000200160001000800042A3Q001600012Q0055000200023Q001230000300053Q001249000400023Q00202Q0004000400034Q00058Q0003000500044Q000200046Q000100033Q00062Q0001002700013Q00042A3Q00270001001230000300064Q002C000400024Q0025000300020002002643000300270001000700042A3Q0027000100260B000200270001000800042A3Q002700012Q0055000200023Q001230000100013Q001230000200094Q0025000100020002002643000100410001000400042A3Q00410001001230000100053Q00062800023Q000100012Q002C8Q000D0001000200020006010001004100013Q00042A3Q00410001001230000300064Q002C000400024Q0025000300020002002643000300410001000A00042A3Q00410001001230000300063Q00201100040002000B2Q0025000300020002002643000300410001000700042A3Q0041000100201100030002000B00260B000300410001000800042A3Q0041000100201100030002000B2Q0055000300024Q0026000100014Q0055000100024Q00333Q00013Q00013Q00043Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F642Q033Q0047455400083Q00121A3Q00016Q00013Q00024Q00025Q00102Q00010002000200302Q0001000300046Q00019Q008Q00017Q00063Q0003043Q007479706503063Q00737472696E67034Q00030A3Q006C6F6164737472696E6703073Q00406D6F64756C650002153Q001230000200014Q002C00036Q0025000200020002002643000200070001000200042A3Q000700010026433Q00090001000300042A3Q000900012Q003600026Q0055000200023Q001230000200044Q002C00035Q0006040004000E0001000100042A3Q000E0001001252000400054Q004F000200040002002643000200120001000600042A3Q001200012Q005300026Q0036000200014Q0055000200024Q00333Q00017Q000B3Q00030F3Q004D6178694875625265706F4F6E6C792Q0103063Q006970616972732Q033Q003F763D03013Q004003053Q00652Q726F7203393Q005B4D415849204855425D20D0A2D0BED0BBD18CD0BAD0BE20D0BED184D0B8D186D0B8D0B0D0BBD18CD0BDD18BD0B920D180D0B5D0BFD0BE3A2003063Q00747970656F6603083Q007265616466696C6503083Q0066756E6374696F6E03063Q00697366696C6502654Q001400026Q001D00020001000200201100030002000100260B000300060001000200042A3Q000600012Q005300036Q0036000300014Q0050000400026Q000500016Q0005000100024Q000600026Q0004000200012Q0014000500034Q001D0005000100020006010003002B00013Q00042A3Q002B0001001230000600034Q002C000700044Q000D00060002000800042A3Q002400012Q0014000B00044Q0039000C000A6Q000D5Q00122Q000E00046Q000F00056Q000C000C000F4Q000B000200024Q000C00056Q000D000B3Q00122Q000E00056Q000F8Q000E000E000F4Q000C000E000200062Q000C002400013Q00042A3Q002400012Q0055000B00023Q000612000600140001000200042A3Q00140001001230000600063Q001252000700074Q002C00086Q00400007000700082Q002F000600020001001230000600083Q001230000700094Q00250006000200020026430006004C0001000A00042A3Q004C0001001230000600083Q0012300007000B4Q00250006000200020026430006004C0001000A00042A3Q004C0001001230000600034Q002C000700014Q000D00060002000800042A3Q004A0001001230000B000B4Q002C000C000A4Q0025000B00020002000601000B004A00013Q00042A3Q004A0001001230000B00094Q003C000C000A6Q000B000200024Q000C00056Q000D000B3Q00122Q000E00056Q000F000A6Q000E000E000F4Q000C000E000200062Q000C004A00013Q00042A3Q004A00012Q0055000B00023Q000612000600390001000200042A3Q00390001001230000600034Q002C000700044Q000D00060002000800042A3Q006000012Q0014000B00044Q0039000C000A6Q000D5Q00122Q000E00046Q000F00056Q000C000C000F4Q000B000200024Q000C00056Q000D000B3Q00122Q000E00056Q000F8Q000E000E000F4Q000C000E000200062Q000C006000013Q00042A3Q006000012Q0055000B00023Q000612000600500001000200042A3Q005000012Q0026000600064Q0055000600024Q00333Q00017Q00043Q0003133Q005F4D617869487562477569526567697374727903053Q007063612Q6C0003113Q005F4D617869487562496E707574436F2Q6E01253Q00201100013Q00010006010001001000013Q00042A3Q0010000100201100013Q00012Q001400026Q002D0001000100020006010001000F00013Q00042A3Q000F0001001230000200023Q00062800033Q000100012Q002C3Q00014Q002F00020002000100201100023Q00012Q001400035Q00201E0002000300032Q000F00015Q00201100013Q00040006010001002000013Q00042A3Q0020000100201100013Q00042Q001400026Q002D0001000100020006010001001F00013Q00042A3Q001F0001001230000200023Q00062800030001000100012Q002C3Q00014Q002F00020002000100201100023Q00042Q001400035Q00201E0002000300032Q000F00015Q001230000100023Q00062800020002000100012Q00148Q002F0001000200012Q00333Q00013Q00033Q00043Q0003063Q00747970656F6603083Q00496E7374616E636503063Q00506172656E7403073Q0044657374726F79000D3Q0012303Q00014Q001400016Q00253Q000200020026433Q000C0001000200042A3Q000C00012Q00147Q0020115Q00030006013Q000C00013Q00042A3Q000C00012Q00147Q0020485Q00042Q002F3Q000200012Q00333Q00017Q00013Q00030A3Q00446973636F2Q6E65637400044Q00147Q0020485Q00012Q002F3Q000200012Q00333Q00017Q00073Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C61796572030E3Q0046696E6446697273744368696C6403093Q00506C6179657247756903073Q0044657374726F7900143Q0012463Q00013Q00206Q000200122Q000200038Q0002000200202Q00013Q000400062Q0002000A0001000100042A3Q000A0001002048000200010005001252000400064Q004F0002000400020006440003000F0001000200042A3Q000F00010020480003000200052Q001400056Q004F0003000500020006010003001300013Q00042A3Q001300010020480004000300072Q002F0004000200012Q00333Q00017Q00063Q0003063Q00747970656F66030B3Q004D61786948756253746F7003083Q0066756E6374696F6E03053Q007063612Q6C03123Q005F4D617869487562436F72654C6F6164656400010D3Q001230000100013Q00201100023Q00022Q0025000100020002002643000100080001000300042A3Q00080001001230000100043Q00201100023Q00022Q002F0001000200012Q001400016Q002C00026Q002F00010002000100301B3Q000500062Q00333Q00017Q000D3Q0003113Q006D6178692D6875622D636F72652E6C7561034Q0003053Q00652Q726F7203483Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D636F72652E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703123Q00406D6178692D6875622D636F72652E6C756103193Q005B4D415849204855425D20636F6D70696C6520636F72653A2003083Q00746F737472696E6703053Q007063612Q6C03153Q005B4D415849204855425D2072756E20636F72653A2003123Q005F4D617869487562436F72654C6F616465642Q0103123Q00726567697374657252656A6F696E482Q6F6B00304Q00279Q003Q000100024Q000100016Q00028Q0001000200014Q000100023Q00122Q000200016Q000300036Q00010003000200062Q0001000D00013Q00042A3Q000D0001002643000100100001000200042A3Q00100001001230000200033Q001252000300044Q002F000200020001001230000200054Q002C000300013Q001252000400064Q00470002000400030006370002001D0001000100042A3Q001D0001001230000400033Q001223000500073Q00122Q000600086Q000700036Q0006000200024Q0005000500064Q000400020001001230000400094Q002C000500024Q000D000400020005000637000400290001000100042A3Q00290001001230000600033Q0012230007000A3Q00122Q000800086Q000900056Q0008000200024Q0007000700084Q00060002000100301B3Q000B000C0012050006000D6Q00078Q0006000200014Q000600016Q000600028Q00017Q00073Q0003063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503053Q007063612Q6C03053Q007461626C65030E3Q0052656A6F696E4175746F4C6F616400263Q0012303Q00013Q001230000100024Q00253Q000200020026433Q000A0001000300042A3Q000A00010012303Q00013Q001230000100044Q00253Q0002000200260B3Q000C0001000300042A3Q000C00012Q00368Q00553Q00023Q0012303Q00024Q001400016Q00253Q000200020006373Q00130001000100042A3Q001300012Q00368Q00553Q00023Q0012303Q00053Q00062800013Q000100012Q00148Q000D3Q000200010006013Q002300013Q00042A3Q00230001001230000200014Q002C000300014Q0025000200020002002643000200230001000600042A3Q002300010020110002000100070006010002002300013Q00042A3Q002300012Q0036000200014Q0055000200024Q003600026Q0055000200024Q00333Q00013Q00013Q00053Q0003043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65000B3Q0012353Q00013Q00206Q000200122Q000200038Q0002000200206Q000400122Q000200056Q00038Q000200039Q009Q008Q00017Q000B3Q0003063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503023Q00727503053Q007063612Q6C03053Q007461626C65030A3Q0055694C616E677561676503063Q00737472696E6703053Q006C6F77657203023Q00656E00303Q0012303Q00013Q001230000100024Q00253Q000200020026433Q000A0001000300042A3Q000A00010012303Q00013Q001230000100044Q00253Q0002000200260B3Q000C0001000300042A3Q000C00010012523Q00054Q00553Q00023Q0012303Q00024Q001400016Q00253Q000200020006373Q00130001000100042A3Q001300010012523Q00054Q00553Q00023Q0012303Q00063Q00062800013Q000100012Q00148Q000D3Q000200010006013Q002D00013Q00042A3Q002D0001001230000200014Q002C000300014Q00250002000200020026430002002D0001000700042A3Q002D0001001230000200013Q0020110003000100082Q00250002000200020026430002002D0001000900042A3Q002D000100201100020001000800204800020002000A2Q00250002000200020026430002002B0001000B00042A3Q002B00010012520002000B3Q0006370002002C0001000100042A3Q002C0001001252000200054Q0055000200023Q001252000200054Q0055000200024Q00333Q00013Q00013Q00053Q0003043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q747053657276696365030A3Q004A534F4E4465636F646503083Q007265616466696C65000B3Q0012353Q00013Q00206Q000200122Q000200038Q0002000200206Q000400122Q000200056Q00038Q000200039Q009Q008Q00017Q00103Q0003043Q007479706503063Q00737472696E6703053Q006C6F77657203023Q00656E03023Q00727503063Q00747970656F6603063Q00697366696C6503083Q0066756E6374696F6E03083Q007265616466696C6503093Q00777269746566696C6503043Q0067616D65030A3Q0047657453657276696365030B3Q00482Q74705365727669636503053Q007063612Q6C03053Q007461626C65030A3Q0055694C616E6775616765013C3Q001230000100014Q002C00026Q00250001000200020026430001000C0001000200042A3Q000C000100204800013Q00032Q00250001000200020026430001000C0001000400042A3Q000C0001001252000100043Q0006043Q000D0001000100042A3Q000D00010012523Q00053Q001230000100063Q001230000200074Q00250001000200020026430001001C0001000800042A3Q001C0001001230000100063Q001230000200094Q00250001000200020026430001001C0001000800042A3Q001C0001001230000100063Q0012300002000A4Q002500010002000200260B0001001D0001000800042A3Q001D00012Q00333Q00013Q0012300001000B3Q00202E00010001000C00122Q0003000D6Q0001000300024Q00025Q00122Q000300076Q00048Q00030002000200062Q0003002D00013Q00042A3Q002D00010012300003000E3Q00062800043Q000100032Q002C3Q00024Q002C3Q00014Q00148Q002F000300020001001230000300064Q002C000400024Q002500030002000200260B000300340001000F00042A3Q003400014Q00036Q002C000200033Q001019000200103Q0012300003000E3Q00062800040001000100032Q00148Q002C3Q00014Q002C3Q00024Q002F0003000200012Q00333Q00013Q00023Q00023Q00030A3Q004A534F4E4465636F646503083Q007265616466696C6500084Q00543Q00013Q00206Q000100122Q000200026Q000300026Q000200039Q0000029Q006Q00017Q00023Q0003093Q00777269746566696C65030A3Q004A534F4E456E636F646500083Q0012153Q00016Q00018Q000200013Q00202Q0002000200024Q000400026Q000200049Q0000016Q00017Q000E3Q0003063Q00747970656F6603113Q0071756575655F6F6E5F74656C65706F727403083Q0066756E6374696F6E03123Q007265616452656A6F696E4175746F4C6F616403143Q005F4D61786948756252656A6F696E5175657565640003103Q004D6178694875624C6F6164657255726C034Q0003193Q006C6F6164737472696E672867616D653A482Q7470476574282203053Q00222Q29282903123Q004D6178694875624F2Q66696369616C526177030F3Q006C6F616465722E6C7561222Q292829032F3Q006C6F6164737472696E67287265616466696C6528226D6178692D6875622F6C61756E636865722E6C7561222Q2928293Q012A3Q001230000100013Q001230000200024Q002500010002000200260B000100060001000300042A3Q000600012Q00333Q00013Q001230000100044Q001D0001000100020006370001000C0001000100042A3Q000C000100301B3Q000500062Q00333Q00013Q00201100013Q00050006010001001000013Q00042A3Q001000012Q00333Q00014Q0026000100013Q00201100023Q00070006010002001C00013Q00042A3Q001C000100201100023Q000700260B0002001C0001000800042A3Q001C0001001252000200093Q00201100033Q00070012520004000A4Q004000010002000400042A3Q0025000100201100023Q000B0006010002002400013Q00042A3Q00240001001252000200093Q00201100033Q000B0012520004000C4Q004000010002000400042A3Q002500010012520001000D3Q001230000200024Q002C000300014Q002F00020002000100301B3Q0005000E2Q00333Q00017Q00013Q0003123Q00726567697374657252656A6F696E482Q6F6B00053Q0012093Q00016Q00018Q000100019Q0000016Q00017Q000A3Q0003103Q006D6178692D6875622D6B65792E6C7561034Q0003053Q00652Q726F7203473Q005B4D415849204855425D20D09DD0B520D0BDD0B0D0B9D0B4D0B5D0BD206D6178692D6875622D6B65792E6C75612028776F726B737061636520D0B8D0BBD0B82047697448756229030A3Q006C6F6164737472696E6703113Q00406D6178692D6875622D6B65792E6C756103183Q005B4D415849204855425D20636F6D70696C65206B65793A2003083Q00746F737472696E6703053Q007063612Q6C03143Q005B4D415849204855425D2072756E206B65793A2000264Q004C7Q00122Q000100016Q000200018Q0002000200064Q000800013Q00042A3Q000800010026433Q000B0001000200042A3Q000B0001001230000100033Q001252000200044Q002F000100020001001230000100054Q002C00025Q001252000300064Q0047000100030002000637000100180001000100042A3Q00180001001230000300033Q001223000400073Q00122Q000500086Q000600026Q0005000200024Q0004000400054Q000300020001001230000300094Q002C000400014Q000D000300020004000637000300240001000100042A3Q00240001001230000500033Q0012230006000A3Q00122Q000700086Q000800046Q0007000200024Q0006000600074Q0005000200012Q0055000400024Q00333Q00017Q000D3Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303083Q0049734C6F6164656403063Q004C6F6164656403043Q0057616974030B3Q004C6F63616C506C61796572030B3Q00506C61796572412Q646564030C3Q0057616974466F724368696C6403093Q00506C61796572477569026Q003E4003053Q00652Q726F72031B3Q005B4D415849204855425D20D09DD0B5D18220506C6179657247756900203Q0012313Q00013Q00206Q000200122Q000200038Q0002000200122Q000100013Q00202Q0001000100044Q00010002000200062Q0001000D0001000100042A3Q000D0001001230000100013Q0020110001000100050020480001000100062Q002F00010002000100201100013Q0007000637000100130001000100042A3Q0013000100201100013Q00080020480001000100062Q00250001000200020020480002000100090012520004000A3Q0012520005000B4Q004F0002000500020006370002001C0001000100042A3Q001C00010012300003000C3Q0012520004000D4Q002F0003000200012Q002C000300014Q002C000400024Q0042000300034Q00333Q00017Q00033Q0003053Q007063612Q6C03043Q007761726E032F3Q005B4D415849204855425D20D09AD180D0B8D182D0B8D187D0B5D181D0BAD0B0D18F20D0BED188D0B8D0B1D0BAD0B03A000A3Q0012303Q00014Q001400016Q000D3Q000200010006373Q00090001000100042A3Q00090001001230000200023Q001252000300034Q002C000400014Q00380002000400012Q00333Q00017Q00123Q0003063Q0063726561746503073Q00776562682Q6F6B03083Q0074656C656772616D03063Q00706C6179657203093Q00706C61796572477569030C3Q0070616E646153657276696365030B3Q00736176654B65795061746803093Q006765744B657955726C03073Q006875624E616D65030C3Q00F09F94B04D41584920485542030A3Q006D617852657472696573026Q00084003083Q006C616E677561676503103Q006F6E4C616E67756167654368616E676503073Q006F6E436C6F7365030E3Q004D6178694875624B65794761746503113Q004D61786948756255694C616E6775616765030C3Q0073686F77417574684761746500284Q00299Q003Q000100024Q000100016Q0001000100024Q000300026Q0003000100024Q000400036Q00040001000200202Q0005000300014Q00063Q000C4Q000700043Q00102Q0006000200074Q000700053Q00102Q00060003000700102Q00060004000100102Q0006000500024Q000700063Q00102Q0006000600074Q000700073Q00102Q0006000700074Q000700083Q00102Q00060008000700302Q00060009000A00302Q0006000B000C00102Q0006000D000400062800073Q000100022Q00143Q00094Q002C7Q0010190006000E000700062800070001000100022Q00143Q000A4Q002C7Q0010450006000F00074Q00050002000200104Q0010000500104Q0011000400202Q0006000500124Q0007000B6Q0006000200016Q00013Q00023Q00013Q0003113Q004D61786948756255694C616E677561676501064Q004E00018Q00028Q0001000200014Q000100013Q00102Q000100018Q00017Q00023Q00030E3Q004D6178694875624B6579476174652Q00064Q00029Q00000100018Q000200016Q00013Q00304Q000100026Q00017Q00243Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C617965727303103Q0055736572496E70757453657276696365030B3Q00482Q747053657276696365030B3Q004C6F63616C506C61796572030B3Q00476574506C6174666F726D03043Q00456E756D03083Q00506C6174666F726D03073Q00416E64726F69642Q033Q00494F5303073Q00414E44524F494403023Q00504303063Q00656D6265647303053Q007469746C6503233Q00D090D0BAD182D0B8D0B2D0B8D180D0BED0B2D0B0D0BD20D181D0BAD180D0B8D0BFD18203053Q00636F6C6F72024Q006069F84003063Q006669656C647303043Q006E616D65030B3Q00446973706C61794E616D6503053Q0076616C756503063Q00696E6C696E652Q0103043Q004E616D6503023Q00494403083Q00746F737472696E6703063Q0055736572496403053Q006A6F62496403053Q004A6F624964010003083Q004578656375746F7203123Q00D09FD0BBD0B0D182D184D0BED180D0BCD0B003063Q00662Q6F74657203043Q007465787403083Q004D4158492048554200513Q0002107Q00123E000100013Q00202Q00010001000200122Q000300036Q00010003000200122Q000200013Q00202Q00020002000200122Q000400046Q00020004000200122Q000300013Q00202Q00030003000200122Q000500056Q00030005000200202Q00040001000600202Q0005000200074Q00050002000200122Q000600083Q00202Q00060006000900202Q00060006000A00062Q0005001A0001000600042A3Q001A0001001230000600083Q00201100060006000900201100060006000B0006320005001D0001000600042A3Q001D00010012520006000C3Q0006370006001E0001000100042A3Q001E00010012520006000D3Q000210000700014Q004100088Q00098Q000A3Q00014Q000B00016Q000C3Q000400302Q000C000F001000302Q000C001100124Q000D00066Q000E3Q000300302Q000E0014001500202Q000F0004001500102Q000E0016000F00302Q000E001700184Q000F3Q000300302Q000F0014001900202Q00100004001900102Q000F0016001000302Q000F001700184Q00103Q000300302Q00100014001A00122Q0011001B3Q00202Q00120004001C4Q00110002000200102Q00100016001100302Q0010001700184Q00113Q000300302Q00110014001D00122Q001200013Q00202Q00120012001E00102Q00110016001200302Q00110017001F4Q00123Q000300302Q0012001400204Q001300076Q00130001000200102Q00120016001300302Q0012001700184Q00133Q000300302Q00130014002100102Q00130016000600302Q0013001700184Q000D00060001001019000C0013000D4Q000D3Q000100301B000D00230024001019000C0022000D2Q0024000B00010001001019000A000E000B2Q00380008000A00012Q00333Q00013Q00023Q00053Q00034Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E03053Q007063612Q6C02113Q0006013Q000400013Q00042A3Q000400010026433Q00050001000100042A3Q000500012Q00333Q00013Q001230000200023Q001230000300034Q002500020002000200260B0002000B0001000400042A3Q000B00012Q00333Q00013Q001230000200053Q00062800033Q000100022Q002C8Q002C3Q00014Q002F0002000200012Q00333Q00013Q00013Q000A3Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030B3Q00482Q747053657276696365030A3Q004A534F4E456E636F6465000F3Q0012083Q00016Q00013Q00044Q00025Q00102Q00010002000200302Q0001000300044Q00023Q000100302Q00020006000700102Q00010005000200122Q000200093Q00202Q00020002000A4Q000400016Q00020004000200102Q0001000800026Q000200016Q00017Q000B3Q0003053Q007063612Q6C03103Q006964656E746966796578656375746F722Q033Q0073796E03073Q007265717565737403093Q0053796E617073652058030B3Q004B524E4C5F4C4F4144454403043Q004B726E6C030E3Q00666C757875735F636F6E7465787403063Q00466C75787573030F3Q006765746578656375746F726E616D6503073Q00556E6B6E6F776E002A3Q0012303Q00013Q001230000100024Q000D3Q000200010006013Q000800013Q00042A3Q000800010006010001000800013Q00042A3Q000800012Q0055000100023Q001230000200033Q0006010002001100013Q00042A3Q00110001001230000200033Q0020110002000200040006010002001100013Q00042A3Q00110001001252000200054Q0055000200023Q001230000200063Q0006010002001600013Q00042A3Q00160001001252000200074Q0055000200023Q001230000200083Q0006010002001B00013Q00042A3Q001B0001001252000200094Q0055000200023Q0012300002000A3Q0006010002002700013Q00042A3Q00270001001230000200013Q0012300003000A4Q000D0002000200030006010002002500013Q00042A3Q00250001000604000400260001000300042A3Q002600010012520004000B4Q0055000400023Q0012520002000B4Q0055000200024Q00333Q00017Q00", GetFEnv(), ...);
