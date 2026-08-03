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
				if (Enum <= 56) then
					if (Enum <= 27) then
						if (Enum <= 13) then
							if (Enum <= 6) then
								if (Enum <= 2) then
									if (Enum <= 0) then
										local A = Inst[2];
										Stk[A](Stk[A + 1]);
									elseif (Enum > 1) then
										local A = Inst[2];
										local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
										local Edx = 0;
										for Idx = A, Inst[4] do
											Edx = Edx + 1;
											Stk[Idx] = Results[Edx];
										end
									else
										local B = Inst[3];
										local K = Stk[B];
										for Idx = B + 1, Inst[4] do
											K = K .. Stk[Idx];
										end
										Stk[Inst[2]] = K;
									end
								elseif (Enum <= 4) then
									if (Enum == 3) then
										local A = Inst[2];
										do
											return Stk[A], Stk[A + 1];
										end
									else
										Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
									end
								elseif (Enum > 5) then
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
								elseif (Stk[Inst[2]] < Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 9) then
								if (Enum <= 7) then
									if (Stk[Inst[2]] == Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum > 8) then
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
									Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							elseif (Enum <= 11) then
								if (Enum == 10) then
									Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
								else
									local A = Inst[2];
									local B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
								end
							elseif (Enum == 12) then
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 20) then
							if (Enum <= 16) then
								if (Enum <= 14) then
									local B = Inst[3];
									local K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
								elseif (Enum > 15) then
									local A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
								else
									Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
								end
							elseif (Enum <= 18) then
								if (Enum == 17) then
									local A = Inst[2];
									local Results = {Stk[A](Stk[A + 1])};
									local Edx = 0;
									for Idx = A, Inst[4] do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								elseif (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 19) then
								Stk[Inst[2]][Inst[3]] = Inst[4];
							else
								Upvalues[Inst[3]] = Stk[Inst[2]];
							end
						elseif (Enum <= 23) then
							if (Enum <= 21) then
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 22) then
								Stk[Inst[2]][Inst[3]] = Inst[4];
							else
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						elseif (Enum <= 25) then
							if (Enum == 24) then
								Stk[Inst[2]] = #Stk[Inst[3]];
							else
								local A = Inst[2];
								local B = Inst[3];
								for Idx = A, B do
									Stk[Idx] = Vararg[Idx - A];
								end
							end
						elseif (Enum == 26) then
							local A = Inst[2];
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
						else
							local B = Stk[Inst[4]];
							if not B then
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = B;
								VIP = Inst[3];
							end
						end
					elseif (Enum <= 41) then
						if (Enum <= 34) then
							if (Enum <= 30) then
								if (Enum <= 28) then
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								elseif (Enum > 29) then
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Top));
								else
									local A = Inst[2];
									do
										return Stk[A](Unpack(Stk, A + 1, Inst[3]));
									end
								end
							elseif (Enum <= 32) then
								if (Enum == 31) then
									local A = Inst[2];
									local Results, Limit = _R(Stk[A]());
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
							elseif (Enum > 33) then
								local A = Inst[2];
								local T = Stk[A];
								local B = Inst[3];
								for Idx = 1, B do
									T[Idx] = Stk[A + Idx];
								end
							elseif Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 37) then
							if (Enum <= 35) then
								do
									return;
								end
							elseif (Enum > 36) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Top));
								end
							else
								local A = Inst[2];
								Stk[A] = Stk[A]();
							end
						elseif (Enum <= 39) then
							if (Enum == 38) then
								Stk[Inst[2]] = Inst[3] ~= 0;
							elseif (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 40) then
							Stk[Inst[2]] = Stk[Inst[3]];
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
					elseif (Enum <= 48) then
						if (Enum <= 44) then
							if (Enum <= 42) then
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Top));
							elseif (Enum > 43) then
								Stk[Inst[2]] = Env[Inst[3]];
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
									if (Mvm[1] == 41) then
										Indexes[Idx - 1] = {Stk,Mvm[3]};
									else
										Indexes[Idx - 1] = {Upvalues,Mvm[3]};
									end
									Lupvals[#Lupvals + 1] = Indexes;
								end
								Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
							end
						elseif (Enum <= 46) then
							if (Enum > 45) then
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
							else
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
							end
						elseif (Enum == 47) then
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
						else
							local A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
						end
					elseif (Enum <= 52) then
						if (Enum <= 50) then
							if (Enum > 49) then
								local A = Inst[2];
								local Results = {Stk[A]()};
								local Limit = Inst[4];
								local Edx = 0;
								for Idx = A, Limit do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								Stk[Inst[2]] = Upvalues[Inst[3]];
							end
						elseif (Enum > 51) then
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
							Top = (A + Varargsz) - 1;
							for Idx = A, Top do
								local VA = Vararg[Idx - A];
								Stk[Idx] = VA;
							end
						end
					elseif (Enum <= 54) then
						if (Enum == 53) then
							Stk[Inst[2]] = Env[Inst[3]];
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
					elseif (Enum == 55) then
						if Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						Stk[Inst[2]] = Inst[3];
					end
				elseif (Enum <= 84) then
					if (Enum <= 70) then
						if (Enum <= 63) then
							if (Enum <= 59) then
								if (Enum <= 57) then
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								elseif (Enum == 58) then
									local A = Inst[2];
									Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
								elseif (Stk[Inst[2]] <= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 61) then
								if (Enum > 60) then
									local A = Inst[2];
									Stk[A](Stk[A + 1]);
								else
									Stk[Inst[2]] = Stk[Inst[3]];
								end
							elseif (Enum > 62) then
								local A = Inst[2];
								local B = Inst[3];
								for Idx = A, B do
									Stk[Idx] = Vararg[Idx - A];
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
						elseif (Enum <= 66) then
							if (Enum <= 64) then
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							elseif (Enum == 65) then
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
							else
								Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
							end
						elseif (Enum <= 68) then
							if (Enum == 67) then
								do
									return;
								end
							elseif (Stk[Inst[2]] == Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 69) then
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Top));
							end
						else
							do
								return Stk[Inst[2]];
							end
						end
					elseif (Enum <= 77) then
						if (Enum <= 73) then
							if (Enum <= 71) then
								if not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum == 72) then
								local A = Inst[2];
								local Results = {Stk[A](Stk[A + 1])};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								do
									return Stk[Inst[2]];
								end
							end
						elseif (Enum <= 75) then
							if (Enum == 74) then
								Stk[Inst[2]] = {};
							elseif (Stk[Inst[2]] <= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 76) then
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
						elseif not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 80) then
						if (Enum <= 78) then
							local A = Inst[2];
							Stk[A] = Stk[A]();
						elseif (Enum > 79) then
							local A = Inst[2];
							do
								return Unpack(Stk, A, A + Inst[3]);
							end
						else
							local A = Inst[2];
							Top = (A + Varargsz) - 1;
							for Idx = A, Top do
								local VA = Vararg[Idx - A];
								Stk[Idx] = VA;
							end
						end
					elseif (Enum <= 82) then
						if (Enum > 81) then
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						elseif (Stk[Inst[2]] ~= Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum == 83) then
						local B = Stk[Inst[4]];
						if not B then
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
				elseif (Enum <= 98) then
					if (Enum <= 91) then
						if (Enum <= 87) then
							if (Enum <= 85) then
								local A = Inst[2];
								do
									return Stk[A](Unpack(Stk, A + 1, Inst[3]));
								end
							elseif (Enum > 86) then
								Stk[Inst[2]] = Inst[3] ~= 0;
							else
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 89) then
							if (Enum > 88) then
								if (Stk[Inst[2]] < Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 90) then
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
					elseif (Enum <= 94) then
						if (Enum <= 92) then
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
						elseif (Enum > 93) then
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
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
					elseif (Enum <= 96) then
						if (Enum == 95) then
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
								if (Mvm[1] == 41) then
									Indexes[Idx - 1] = {Stk,Mvm[3]};
								else
									Indexes[Idx - 1] = {Upvalues,Mvm[3]};
								end
								Lupvals[#Lupvals + 1] = Indexes;
							end
							Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
						else
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum > 97) then
						Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
					else
						Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
					end
				elseif (Enum <= 105) then
					if (Enum <= 101) then
						if (Enum <= 99) then
							local A = Inst[2];
							do
								return Stk[A], Stk[A + 1];
							end
						elseif (Enum == 100) then
							Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
						else
							Stk[Inst[2]] = Upvalues[Inst[3]];
						end
					elseif (Enum <= 103) then
						if (Enum == 102) then
							if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
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
					elseif (Enum == 104) then
						Stk[Inst[2]] = #Stk[Inst[3]];
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 109) then
					if (Enum <= 107) then
						if (Enum == 106) then
							if (Stk[Inst[2]] < Inst[4]) then
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
					elseif (Enum == 108) then
						local A = Inst[2];
						local T = Stk[A];
						local B = Inst[3];
						for Idx = 1, B do
							T[Idx] = Stk[A + Idx];
						end
					else
						Stk[Inst[2]] = {};
					end
				elseif (Enum <= 111) then
					if (Enum > 110) then
						Upvalues[Inst[3]] = Stk[Inst[2]];
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
				elseif (Enum == 112) then
					if (Stk[Inst[2]] < Inst[4]) then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				else
					local A = Inst[2];
					Stk[A] = Stk[A](Stk[A + 1]);
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!683Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47030E3Q004D617869487562536B69704B65792Q01030F3Q005F4D617869487562417574684C6962031A3Q006D6178692D6875622F6D6178692D6875622D617574682E6C756103113Q006D6178692D6875622D617574682E6C756103043Q007479706503103Q004D6178694875624C6F63616C522Q6F7403063Q00737472696E67034Q0003053Q007461626C6503063Q00696E73657274026Q00F03F03123Q002F6D6178692D6875622D617574682E6C756103083Q007265616466696C6503063Q00697366696C6503063Q0069706169727303123Q004D6178694875624F2Q66696369616C52617703113Q004D61786948756252656D6F74654261736503043Q0067616D6503073Q00482Q747047657403053Q007063612Q6C03053Q00652Q726F72032B3Q005B4D415849204855425D204D692Q73696E67206D6178692D6875622D617574682E6C756120286B69636B29030A3Q006C6F6164737472696E6703123Q00406D6178692D6875622D617574682E6C756103193Q005B4D415849204855425D206175746820636F6D70696C653A2003083Q00746F737472696E6703113Q005B4D415849204855425D20617574683A2003053Q00677561726403043Q006B69636B030A3Q0047657453657276696365030B3Q00482Q74705365727669636503073Q00506C6179657273030A3Q0047756953657276696365030F3Q0054656C65706F72745365727669636503073Q00436F7265477569030A3Q0052756E5365727669636503193Q0068656164736574646973636F2Q6E656374652Q6469616C6F6703133Q0068656164736574646973636F2Q6E6563746564030F3Q00762Q72656D6F76616C6469616C6F6703093Q00726F626C6F7867756903043Q0063686174030A3Q00706C617965726C697374030A3Q00656D6F7465736D656E7503083Q006261636B7061636B030A3Q007374617274657267756903053Q006C6162656C03023Q006F6B03063Q00612Q6365707403073Q006465636C696E6503063Q0063616E63656C03053Q00636C6F73652Q033Q0079657303023Q006E6F03073Q00672Q6F646279652Q033Q003Q2E03093Q005E726573746172742403143Q006865616473657420646973636F2Q6E656374656403163Q00706C6561736520726573746172742074686520612Q7003233Q00746F20636F6E74696E756520706C6179696E672C20706C65617365207265737461727403153Q00747269616E676C65252D6578636C616D6174696F6E03143Q00747269616E676C65206578636C616D6174696F6E03083Q007567636974656D7303103Q0062617463686974656D64657461696C7303113Q00742Q6F206D616E7920726571756573747303083Q00682Q74702034323903083Q00682Q747020353033030B3Q00746578746368612Q6E656C03113Q006F6E696E636F6D696E676D652Q73616765030E3Q006173796E632063612Q6C6261636B03123Q0068617320622Q656E2064657374726F796564030D3Q006661696C656420746F20676574030C3Q00747279696E6720616761696E030A3Q0072617465206C696D6974030D3Q00612Q73657464656C6976657279030F3Q00636F6E74656E7470726F766964657203133Q006D657368636F6E74656E7470726F766964657203103Q00696E76616C696420757365726E616D65030E3Q006661696C656420746F206C6F6164030E3Q00696E66696E697465207969656C6403063Q006B69636B656403063Q0062612Q6E65642Q033Q0062616E030A3Q00646973636F2Q6E656374030C3Q00646973636F2Q6E656374656403073Q0072656D6F76656403083Q00657870652Q6C656403093Q006D6F64657261746F72030A3Q006D6F6465726174696F6E03093Q0076696F6C6174696F6E03053Q00636865617403073Q006578706C6F6974030A3Q007465726D696E6174656403093Q0073757370656E646564030B3Q00652Q726F7270726F6D7074030C3Q00652Q726F726D652Q7361676503093Q006C6561766567616D65030D3Q00636F6E6669726D6469616C6F67030D3Q00756E6976657273616C636F726503053Q0073746172740014012Q0012353Q00013Q001235000100024Q00713Q000200020026153Q0009000100030004693Q000900010012353Q00024Q00243Q0001000200064D3Q000A000100010004693Q000A00010012353Q00043Q00206200013Q000500261200010077000100060004693Q0077000100206200013Q000700064D00010074000100010004693Q007400012Q002E000200024Q006D000300023Q001238000400083Q001238000500094Q006C0003000200010012350004000A3Q00206200053Q000B2Q0071000400020002002615000400250001000C0004693Q0025000100206200043Q000B002612000400250001000D0004693Q002500010012350004000E3Q00206200040004000F2Q003C000500033Q001238000600103Q00206200073Q000B001238000800114Q000E0007000700082Q0008000400070001001235000400013Q001235000500124Q00710004000200020026150004003F000100030004693Q003F0001001235000400013Q001235000500134Q00710004000200020026150004003F000100030004693Q003F0001001235000400144Q003C000500034Q00480004000200060004693Q003D0001001235000900134Q003C000A00084Q00710009000200020006210009003D00013Q0004693Q003D0001001235000900124Q003C000A00084Q00710009000200022Q003C000200093Q0004693Q003F000100065B00040033000100020004693Q0033000100064D00020053000100010004693Q0053000100206200043Q001500064D00040045000100010004693Q0045000100206200043Q00160006210004005200013Q0004693Q00520001001235000500013Q001235000600173Q0020620006000600182Q007100050002000200261500050052000100030004693Q00520001001235000500193Q00062B00063Q000100022Q00293Q00024Q00293Q00046Q0005000200012Q003600045Q00064D00020058000100010004693Q005800010012350004001A3Q0012380005001B6Q0004000200010012350004001C4Q003C000500023Q0012380006001D4Q005400040006000500064D00040065000100010004693Q006500010012350006001A3Q0012380007001E3Q0012350008001F4Q003C000900054Q00710008000200022Q000E0007000700084Q000600020001001235000600194Q003C000700044Q004800060002000700064D00060071000100010004693Q007100010012350008001A3Q001238000900203Q001235000A001F4Q003C000B00074Q0071000A000200022Q000E00090009000A4Q0008000200012Q003C000100073Q0010523Q000700012Q003600025Q002062000200010021001238000300226Q0002000200010012353Q00173Q00200B5Q0023001238000200244Q00173Q00020002001235000100173Q00200B000100010023001238000300254Q0017000100030002001235000200173Q00200B000200020023001238000400264Q0017000200040002001235000300173Q00200B000300030023001238000500274Q0017000300050002001235000400173Q00200B000400040023001238000600284Q0017000400060002001235000500173Q00200B000500050023001238000700294Q00170005000700022Q006D00066Q006D00073Q00090030140007002A00060030140007002B00060030140007002C00060030140007002D00060030140007002E00060030140007002F00060030140007003000060030140007003100060030140007003200062Q006D00083Q000A0030140008003300060030140008003400060030140008003500060030140008003600060030140008003700060030140008003800060030140008003900060030140008003A00060030140008003B00060030140008003C00062Q006D000900063Q001238000A003D3Q001238000B003E3Q001238000C003F3Q001238000D00403Q001238000E00413Q001238000F00424Q006C0009000600012Q006D000A00113Q001238000B00433Q001238000C00443Q001238000D00453Q001238000E00463Q001238000F00473Q001238001000483Q001238001100493Q0012380012004A3Q0012380013004B3Q0012380014004C3Q0012380015004D3Q0012380016004E3Q0012380017004F3Q001238001800503Q001238001900513Q001238001A00523Q001238001B00533Q001238001C00544Q006C000A001200012Q006D000B000F3Q001238000C00223Q001238000D00553Q001238000E00563Q001238000F00573Q001238001000583Q001238001100593Q0012380012005A3Q0012380013005B3Q0012380014005C3Q0012380015005D3Q0012380016005E3Q0012380017005F3Q001238001800603Q001238001900613Q001238001A00624Q006C000B000F00012Q006D000C00083Q001238000D00633Q001238000E00643Q001238000F00583Q001238001000223Q001238001100573Q001238001200653Q001238001300663Q001238001400674Q006C000C0008000100020F000D00013Q00062B000E0002000100022Q00293Q000D4Q00293Q00093Q00062B000F0003000100012Q00293Q000E3Q00062B00100004000100012Q00293Q00073Q00062B00110005000100022Q00293Q000D4Q00293Q00083Q00062B00120006000100012Q00293Q000A3Q00062B00130007000100012Q00293Q00123Q00062B00140008000100032Q00293Q00124Q00293Q00104Q00293Q000F3Q00062B00150009000100012Q00293Q000C3Q00062B0016000A000100012Q00293Q000B3Q00062B0017000B000100032Q00293Q00114Q00293Q000E4Q00293Q00163Q00062B0018000C000100022Q00293Q00144Q00293Q00153Q00020F0019000D3Q00062B001A000E000100012Q00293Q00103Q00020F001B000F3Q00062B001C0010000100122Q00293Q00014Q00293Q001B4Q00298Q00293Q00174Q00293Q00144Q00293Q00114Q00293Q00044Q00293Q00024Q00293Q000F4Q00293Q00194Q00293Q00104Q00293Q00154Q00293Q00184Q00293Q001A4Q00293Q00034Q00293Q00164Q00293Q00134Q00293Q00053Q00105200060068001C2Q0045000600024Q00433Q00013Q00113Q00063Q0003043Q0067616D6503073Q00482Q747047657403143Q006D6178692D6875622D617574682E6C75613F763D03083Q00746F737472696E6703023Q006F7303043Q0074696D65000E3Q0012353Q00013Q00200B5Q00022Q0065000200013Q001238000300033Q001235000400043Q001235000500053Q0020620005000500062Q001F000500014Q003A00043Q00022Q000E0002000200042Q0057000300014Q00173Q000300022Q006F8Q00433Q00017Q00073Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203043Q006773756203043Q005E25732B03043Q0025732B2401143Q001235000100014Q003C00026Q007100010002000200261200010007000100020004693Q00070001001238000100034Q0045000100023Q001235000100023Q00206200010001000400200B00023Q0005001238000400063Q001238000500034Q001700020005000200200B000200020005001238000400073Q001238000500034Q005A000200054Q004600016Q002000016Q00433Q00017Q00053Q00034Q0003063Q0069706169727303043Q0066696E64026Q00F03F03053Q006D61746368011E4Q006500016Q003C00026Q007100010002000200261500010007000100010004693Q000700012Q0057000200014Q0045000200023Q001235000200024Q0065000300014Q00480002000200040004693Q0019000100200B0007000100032Q003C000900063Q001238000A00044Q0057000B00014Q00170007000B000200064D00070017000100010004693Q0017000100200B0007000100052Q003C000900064Q00170007000900020006210007001900013Q0004693Q001900012Q0057000700014Q0045000700023Q00065B0002000B000100020004693Q000B00012Q005700026Q0045000200024Q00433Q00017Q00083Q0003043Q007479706503063Q00737472696E67034Q0003063Q00676D6174636803063Q005B5E0D0A5D2B03043Q006773756203043Q005E25732B03043Q0025732B2401243Q001235000100014Q003C00026Q007100010002000200261500010007000100020004693Q000700010026153Q0009000100030004693Q000900012Q005700016Q0045000100024Q005700015Q00200B00023Q0004001238000400054Q00540002000400040004693Q0020000100200B000600050006001238000800073Q001238000900034Q001700060009000200200B000600060006001238000800083Q001238000900034Q001700060009000200261200060020000100030004693Q002000012Q0057000100014Q006500076Q003C000800064Q007100070002000200064D00070020000100010004693Q002000012Q005700076Q0045000700023Q00065B0002000E000100010004693Q000E00012Q0045000100024Q00433Q00017Q00083Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203043Q0066696E6403133Q0068656164736574646973636F2Q6E6563746564026Q00F03F00011E3Q001235000100014Q003C00026Q007100010002000200261500010007000100020004693Q000700010026153Q0009000100030004693Q000900012Q005700016Q0045000100023Q001235000100023Q0020620001000100042Q003C00026Q00710001000200022Q006500026Q00390002000200010006210002001300013Q0004693Q001300012Q0057000200014Q0045000200023Q00200B000200010005001238000400063Q001238000500074Q0057000600014Q00170002000600020026150002001B000100080004693Q001B00012Q002D00026Q0057000200014Q0045000200024Q00433Q00017Q00023Q00034Q00027Q004001154Q006500016Q003C00026Q007100010002000200261500010007000100010004693Q000700012Q0057000200014Q0045000200024Q0065000200014Q00390002000200010006210002000D00013Q0004693Q000D00012Q0057000200014Q0045000200024Q0018000200013Q00263B00020012000100020004693Q001200012Q0057000200014Q0045000200024Q005700026Q0045000200024Q00433Q00017Q00073Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203063Q0069706169727303043Q0066696E64026Q00F03F011F3Q001235000100014Q003C00026Q007100010002000200261500010007000100020004693Q000700010026153Q0009000100030004693Q000900012Q005700016Q0045000100023Q001235000100023Q0020620001000100042Q003C00026Q0071000100020002001235000200054Q006500036Q00480002000200040004693Q001A000100200B0007000100062Q003C000900063Q001238000A00074Q0057000B00014Q00170007000B00020006210007001A00013Q0004693Q001A00012Q0057000700014Q0045000700023Q00065B00020011000100020004693Q001100012Q005700026Q0045000200024Q00433Q00017Q000D3Q0003043Q007479706503063Q00737472696E67034Q0003113Q006C2Q6F6B734C696B654B69636B5465787403053Q006C6F77657203043Q0066696E6403113Q00646973636F2Q6E65637465642066726F6D026Q00F03F030F3Q006C6F737420636F2Q6E656374696F6E03143Q00796F75206861766520622Q656E206B69636B656403143Q00796F75206861766520622Q656E2062612Q6E6564030A3Q006D6F6465726174696F6E030A3Q00646973636F2Q6E65637401523Q001235000100014Q003C00026Q007100010002000200261500010007000100020004693Q000700010026153Q0009000100030004693Q000900012Q005700016Q0045000100024Q006500016Q003C00026Q00710001000200020006210001001000013Q0004693Q001000012Q005700016Q0045000100023Q001235000100044Q003C00026Q00710001000200020006210001001700013Q0004693Q001700012Q0057000100014Q0045000100023Q001235000100023Q0020620001000100052Q003C00026Q007100010002000200200B000200010006001238000400073Q001238000500084Q0057000600014Q00170002000600020006210002002400013Q0004693Q002400012Q0057000200014Q0045000200023Q00200B000200010006001238000400093Q001238000500084Q0057000600014Q00170002000600020006210002002D00013Q0004693Q002D00012Q0057000200014Q0045000200023Q00200B0002000100060012380004000A3Q001238000500084Q0057000600014Q00170002000600020006210002003600013Q0004693Q003600012Q0057000200014Q0045000200023Q00200B0002000100060012380004000B3Q001238000500084Q0057000600014Q00170002000600020006210002003F00013Q0004693Q003F00012Q0057000200014Q0045000200023Q00200B0002000100060012380004000C3Q001238000500084Q0057000600014Q00170002000600020006210002004F00013Q0004693Q004F000100200B0002000100060012380004000D3Q001238000500084Q0057000600014Q00170002000600020006210002004F00013Q0004693Q004F00012Q0057000200014Q0045000200024Q005700026Q0045000200024Q00433Q00017Q00073Q0003063Q00737472696E6703053Q006C6F77657203083Q00746F737472696E67034Q0003043Q0066696E6403133Q0068656164736574646973636F2Q6E6563746564026Q00F03F03294Q006500036Q003C000400014Q00710003000200020006210003000700013Q0004693Q000700012Q0057000300014Q0045000300024Q0065000300014Q003C000400024Q00710003000200020006210003000E00013Q0004693Q000E00012Q0057000300014Q0045000300024Q0065000300024Q003C000400014Q00710003000200020006210003001500013Q0004693Q001500012Q0057000300014Q0045000300023Q001235000300013Q002062000300030002001235000400033Q00061B0005001B00013Q0004693Q001B0001001238000500044Q0009000400054Q003A00033Q000200200B000400030005001238000600063Q001238000700074Q0057000800014Q00170004000800020006210004002600013Q0004693Q002600012Q0057000400014Q0045000400024Q005700046Q0045000400024Q00433Q00017Q00073Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203063Q0069706169727303043Q0066696E64026Q00F03F011F3Q001235000100014Q003C00026Q007100010002000200261500010007000100020004693Q000700010026153Q0009000100030004693Q000900012Q005700016Q0045000100023Q001235000100023Q0020620001000100042Q003C00026Q0071000100020002001235000200054Q006500036Q00480002000200040004693Q001A000100200B0007000100062Q003C000900063Q001238000A00074Q0057000B00014Q00170007000B00020006210007001A00013Q0004693Q001A00012Q0057000700014Q0045000700023Q00065B00020011000100020004693Q001100012Q005700026Q0045000200024Q00433Q00017Q00073Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203063Q0069706169727303043Q0066696E64026Q00F03F01213Q001235000100014Q003C00026Q007100010002000200261500010007000100020004693Q000700010026153Q0009000100030004693Q000900012Q005700016Q0045000100023Q001235000100023Q0020620001000100042Q003C00026Q0071000100020002001235000200054Q006500036Q00480002000200040004693Q001C0001001235000700023Q0020620007000700062Q003C000800014Q003C000900063Q001238000A00074Q0057000B00014Q00170007000B00020006210007001C00013Q0004693Q001C00012Q0057000700014Q0045000700023Q00065B00020011000100020004693Q001100012Q005700026Q0045000200024Q00433Q00017Q000A3Q0003043Q007479706503063Q00737472696E67034Q00026Q00F0BF03063Q00676D6174636803063Q005B5E0D0A5D2B03043Q006773756203043Q005E25732B03043Q0025732B24026Q00694001523Q001235000100014Q003C00026Q007100010002000200261500010007000100020004693Q000700010026153Q0009000100030004693Q00090001001238000100034Q0045000100023Q001238000100033Q001238000200043Q00200B00033Q0005001238000500064Q00540003000500050004693Q002F000100200B000700060007001238000900083Q001238000A00034Q00170007000A000200200B000700070007001238000900093Q001238000A00034Q00170007000A00020026120007002F000100030004693Q002F00012Q006500086Q003C000900074Q007100080002000200064D0008002F000100010004693Q002F00012Q0065000800014Q003C000900074Q00710008000200020006210008002400013Q0004693Q002400010004693Q002F00012Q0018000800074Q0065000900024Q003C000A00074Q00710009000200020006210009002B00013Q0004693Q002B000100200A00080008000A0006050002002F000100080004693Q002F00012Q003C000200084Q003C000100073Q00065B0003000F000100010004693Q000F000100261200010034000100030004693Q003400012Q0045000100023Q00200B00033Q0005001238000500064Q00540003000500050004693Q004D000100200B000700060007001238000900083Q001238000A00034Q00170007000A000200200B000700070007001238000900093Q001238000A00034Q00170007000A00020026120007004D000100030004693Q004D00012Q006500086Q003C000900074Q007100080002000200064D0008004D000100010004693Q004D00012Q0065000800014Q003C000900074Q007100080002000200064D0008004D000100010004693Q004D00012Q0045000700023Q00065B00030038000100010004693Q00380001001238000300034Q0045000300024Q00433Q00017Q00033Q0003043Q007479706503063Q00737472696E67034Q0002174Q006500026Q002E000300034Q003C00046Q003C000500014Q00170002000500020006210002000900013Q0004693Q000900012Q005700026Q0045000200023Q001235000200014Q003C00036Q007100020002000200261500020012000100020004693Q001200010026123Q0012000100030004693Q001200012Q0057000200014Q0045000200024Q0065000200014Q003C000300014Q001D000200034Q002000026Q00433Q00017Q00093Q0003063Q00747970656F6603083Q00456E756D4974656D03083Q00746F737472696E6703083Q00456E756D54797065030F3Q00436F2Q6E656374696F6E452Q726F7203043Q00456E756D03103Q00446973636F2Q6E656374452Q726F727303113Q00506C6163656C61756E6368452Q726F7273030E3Q0054656C65706F7274452Q726F727301213Q001235000100014Q003C00026Q007100010002000200261200010007000100020004693Q000700012Q005700016Q0045000100023Q001235000100033Q00206200023Q00042Q00710001000200020026150001000E000100050004693Q000E00012Q0057000200014Q0045000200023Q001235000200063Q0020620002000200050020620002000200070006513Q001E000100020004693Q001E0001001235000200063Q0020620002000200050020620002000200080006513Q001E000100020004693Q001E0001001235000200063Q0020620002000200050020620002000200090006513Q001E000100020004693Q001E00012Q002D00026Q0057000200014Q0045000200024Q00433Q00017Q00023Q0003043Q004E616D6503053Q007063612Q6C01123Q00064D3Q0004000100010004693Q000400012Q005700016Q0045000100024Q006500015Q00206200023Q00012Q00710001000200020006210001000F00013Q0004693Q000F0001001235000100023Q00062B00023Q000100012Q00299Q000001000200012Q0057000100014Q0045000100024Q005700016Q0045000100024Q00433Q00013Q00013Q00013Q0003073Q0044657374726F7900044Q00657Q00200B5Q00016Q000200012Q00433Q00017Q00053Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E2Q033Q0073796E03043Q00682Q747001243Q001235000100013Q001235000200024Q007100010002000200261500010009000100030004693Q00090001001235000100024Q003C00026Q001D000100024Q002000015Q001235000100043Q0006210001001500013Q0004693Q00150001001235000100043Q0020620001000100020006210001001500013Q0004693Q00150001001235000100043Q0020620001000100022Q003C00026Q001D000100024Q002000015Q001235000100053Q0006210001002100013Q0004693Q00210001001235000100053Q0020620001000100020006210001002100013Q0004693Q00210001001235000100053Q0020620001000100022Q003C00026Q001D000100024Q002000016Q002E000100014Q0045000100024Q00433Q00017Q000E3Q00030A3Q00676574576562682Q6F6B03083Q00676574537461747303013Q004C030E3Q0067657445787472614669656C647303073Q006C6F6746696C6503173Q006D6178692D6875622D6C6173742D6B69636B2E6A736F6E03063Q00706C61796572030B3Q004C6F63616C506C61796572030B3Q00682Q74705265717565737403063Q007265706F727403043Q0073746F7003053Q007063612Q6C03053Q007072696E74031E3Q005B4D415849204855425D204B69636B206D6F6E69746F722061637469766501AB3Q00064D3Q0004000100010004693Q000400012Q006D00016Q003C3Q00013Q00206200013Q000100206200023Q000200206200033Q000300064D0003000A000100010004693Q000A000100020F00035Q00206200043Q000400206200053Q000500064D0005000F000100010004693Q000F0001001238000500063Q00206200063Q000700064D00060014000100010004693Q001400012Q006500065Q00206200060006000800206200073Q000900064D00070018000100010004693Q001800012Q0065000700013Q00062B00080001000100022Q00293Q00014Q00298Q005700096Q006D000A6Q0057000B6Q002E000C000D3Q00062B000E0002000100012Q00293Q000A3Q00062B000F0003000100012Q00293Q000A3Q00062B00100004000100022Q00293Q00054Q00313Q00023Q00062B00110005000100042Q00293Q00034Q00293Q00064Q00293Q00024Q00293Q00043Q00062B001200060001000D2Q00293Q000B4Q00313Q00034Q00313Q00044Q00293Q000C4Q00293Q000D4Q00293Q00064Q00293Q00104Q00293Q00054Q00293Q00084Q00293Q00074Q00313Q00024Q00293Q00034Q00293Q00113Q00062B00130007000100032Q00313Q00044Q00293Q000C4Q00293Q000D3Q00062B00140008000100012Q00313Q00053Q00062B00150009000100012Q00313Q00063Q00062B0016000A000100092Q00313Q00074Q00313Q00084Q00313Q00034Q00313Q00094Q00313Q00064Q00313Q000A4Q00313Q000B4Q00293Q00144Q00313Q000C3Q00062B0017000B000100092Q00313Q000D4Q00293Q00154Q00313Q000A4Q00313Q000B4Q00293Q00144Q00313Q00034Q00313Q000C4Q00293Q00134Q00293Q00123Q00062B0018000C000100032Q00313Q000D4Q00313Q000B4Q00293Q00173Q00062B0019000D000100032Q00293Q00064Q00318Q00293Q00123Q00062B001A000E000100062Q00293Q000E4Q00313Q00074Q00313Q00094Q00313Q00034Q00313Q000C4Q00293Q00123Q00062B001B000F000100052Q00293Q000E4Q00313Q000E4Q00313Q000C4Q00313Q000F4Q00293Q00123Q00062B001C0010000100052Q00313Q000D4Q00293Q00184Q00313Q00064Q00293Q000E4Q00313Q000B3Q00062B001D0011000100042Q00293Q000E4Q00313Q00104Q00293Q00134Q00293Q00123Q00062B001E0012000100092Q00293Q00064Q00318Q00293Q000E4Q00293Q000B4Q00293Q00164Q00293Q000C4Q00293Q000D4Q00313Q000C4Q00293Q00123Q00062B001F0013000100072Q00293Q000E4Q00313Q00114Q00293Q000B4Q00293Q00164Q00313Q000C4Q00293Q00134Q00293Q00123Q0006210009008D00013Q0004693Q008D00012Q006D00203Q00020010520020000A00120010520020000B000F2Q0045002000024Q0057000900013Q0012350020000C4Q003C002100196Q0020000200010012350020000C4Q003C0021001A6Q0020000200010012350020000C4Q003C0021001B6Q0020000200010012350020000C4Q003C0021001C6Q0020000200010012350020000C4Q003C0021001D6Q0020000200010012350020000C4Q003C0021001E6Q0020000200010012350020000C4Q003C0021001F6Q0020000200010012350020000D3Q0012380021000E6Q0020000200012Q006D00203Q00020010520020000A00120010520020000B000F2Q0045002000024Q00433Q00013Q00147Q0001024Q00453Q00024Q00433Q00017Q000A3Q0003063Q00747970656F6603083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503063Q00737472696E6703043Q006773756203043Q005E25732B034Q0003043Q0025732B2403073Q00776562682Q6F6B00313Q0012353Q00014Q006500016Q00713Q000200020026153Q001B000100020004693Q001B00010012353Q00034Q006500016Q00483Q000200010006213Q001B00013Q0004693Q001B0001001235000200044Q003C000300014Q00710002000200020026150002001B000100050004693Q001B000100200B000200010006001238000400073Q001238000500084Q001700020005000200200B000200020006001238000400093Q001238000500084Q00170002000500022Q003C000100023Q0026120001001B000100080004693Q001B00012Q0045000100024Q00653Q00013Q0020625Q000A00064D3Q0020000100010004693Q002000010012383Q00083Q001235000100044Q003C00026Q00710001000200020026150001002E000100050004693Q002E000100200B00013Q0006001238000300073Q001238000400084Q001700010004000200200B000100010006001238000300093Q001238000400084Q001D000100044Q002000015Q001238000100084Q0045000100024Q00433Q00017Q00023Q0003053Q007461626C6503063Q00696E7365727401083Q0006213Q000700013Q0004693Q00070001001235000100013Q0020620001000100022Q006500026Q003C00036Q00080001000300012Q00433Q00017Q00043Q0003063Q0069706169727303053Q007063612Q6C03053Q007461626C6503053Q00636C65617200103Q0012353Q00014Q006500016Q00483Q000200020004693Q00090001001235000500023Q00062B00063Q000100012Q00293Q00046Q0005000200012Q003600035Q00065B3Q0004000100020004693Q000400010012353Q00033Q0020625Q00042Q006500019Q00000200012Q00433Q00013Q00013Q00013Q00030A3Q00446973636F2Q6E65637400044Q00657Q00200B5Q00016Q000200012Q00433Q00017Q00043Q0003063Q00747970656F6603093Q00777269746566696C6503083Q0066756E6374696F6E03053Q007063612Q6C010D3Q001235000100013Q001235000200024Q007100010002000200261200010006000100030004693Q000600012Q00433Q00013Q001235000100043Q00062B00023Q000100032Q00318Q00313Q00014Q00299Q000001000200012Q00433Q00013Q00013Q00023Q0003093Q00777269746566696C65030A3Q004A534F4E456E636F646500083Q0012353Q00014Q006500016Q0065000200013Q00200B0002000200022Q0065000400024Q005A000200044Q001E5Q00012Q00433Q00017Q00313Q0003043Q006E616D6503113Q006B69636B5F6669656C645F736F7572636503053Q0076616C756503083Q00746F737472696E6703063Q00696E6C696E652Q0103113Q006B69636B5F6669656C645F726561736F6E2Q033Q00737562026Q00F03F025Q00208C40010003113Q006B69636B5F6669656C645F706C6179657203043Q004E616D652Q033Q0020286003063Q0055736572496403023Q00602903013Q003F03103Q006B69636B5F6669656C645F706C61636503043Q0067616D6503073Q00506C6163654964030E3Q006B69636B5F6669656C645F6A6F6203053Q004A6F624964030D3Q006B69636B5F6669656C645F617403023Q006F7303043Q006461746503113Q0025592D256D2D25642025483A254D3A255303063Q00747970656F6603083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503053Q007461626C6503053Q00706861736503063Q00696E7365727403103Q006B69636B5F6669656C645F7068617365030A3Q0074722Q65734D696E6564030B3Q0073746F6E65734D696E656403123Q006B69636B5F6669656C645F73652Q73696F6E03063Q00737472696E6703063Q00666F726D6174030B3Q0025733A25732025733A2573030A3Q006D6F64655F74722Q6573028Q00030B3Q006D6F64655F73746F6E6573030C3Q006661726D54696D6554657874030B3Q006661726D5365636F6E6473030F3Q006B69636B5F6669656C645F74696D6503063Q0069706169727303053Q007061697273026Q00694003E64Q006D000300064Q006D00043Q00032Q006500055Q001238000600024Q0071000500020002001052000400010005001235000500044Q003C00066Q00710005000200020010520004000300050030140004000500062Q006D00053Q00032Q006500065Q001238000700074Q0071000600020002001052000500010006001235000600044Q003C000700014Q007100060002000200200B000600060008001238000800093Q0012380009000A4Q001700060009000200105200050003000600301400050005000B2Q006D00063Q00032Q006500075Q0012380008000C4Q00710007000200020010520006000100072Q0065000700013Q0006210007002A00013Q0004693Q002A00012Q0065000700013Q00206200070007000D0012380008000E4Q0065000900013Q00206200090009000F001238000A00104Q000E00070007000A00064D0007002B000100010004693Q002B0001001238000700113Q00105200060003000700301400060005000B2Q006D00073Q00032Q006500085Q001238000900124Q0071000800020002001052000700010008001235000800043Q001235000900133Q0020620009000900142Q00710008000200020010520007000300080030140007000500062Q006D00083Q00032Q006500095Q001238000A00154Q0071000900020002001052000800010009001235000900043Q001235000A00133Q002062000A000A00162Q00710009000200020010520008000300090030140008000500062Q006D00093Q00032Q0065000A5Q001238000B00174Q0071000A0002000200105200090001000A001235000A00183Q002062000A000A0019001238000B001A4Q0071000A0002000200105200090003000A0030140009000500062Q006C0003000600010012350004001B4Q0065000500024Q0071000400020002002615000400AD0001001C0004693Q00AD00010012350004001D4Q0065000500024Q0048000400020005000621000400AD00013Q0004693Q00AD00010012350006001E4Q003C000700054Q0071000600020002002615000600AD0001001F0004693Q00AD00010020620006000500200006210006006F00013Q0004693Q006F00010012350006001F3Q0020620006000600212Q003C000700034Q006D00083Q00032Q006500095Q001238000A00224Q0071000900020002001052000800010009001235000900043Q002062000A000500202Q00710009000200020010520008000300090030140008000500062Q000800060008000100206200060005002300064D00060075000100010004693Q007500010020620006000500240006210006009600013Q0004693Q009600010012350006001F3Q0020620006000600212Q003C000700034Q006D00083Q00032Q006500095Q001238000A00254Q0071000900020002001052000800010009001235000900263Q002062000900090027001238000A00284Q0065000B5Q001238000C00294Q0071000B00020002001235000C00043Q002062000D0005002300064D000D0088000100010004693Q00880001001238000D002A4Q0071000C000200022Q0065000D5Q001238000E002B4Q0071000D00020002001235000E00043Q002062000F0005002400064D000F0091000100010004693Q00910001001238000F002A4Q0009000E000F4Q003A00093Q00020010520008000300090030140008000500062Q000800060008000100206200060005002C00064D0006009C000100010004693Q009C000100206200060005002D000621000600AD00013Q0004693Q00AD00010012350006001F3Q0020620006000600212Q003C000700034Q006D00083Q00032Q006500095Q001238000A002E4Q0071000900020002001052000800010009001235000900043Q002062000A0005002C00064D000A00A9000100010004693Q00A90001002062000A0005002D2Q00710009000200020010520008000300090030140008000500062Q00080006000800010012350004001B4Q0065000500034Q0071000400020002002615000400C70001001C0004693Q00C700010012350004001D4Q0065000500034Q0048000400020005000621000400C700013Q0004693Q00C700010012350006001E4Q003C000700054Q0071000600020002002615000600C70001001F0004693Q00C700010012350006002F4Q003C000700054Q00480006000200080004693Q00C50001001235000B001F3Q002062000B000B00212Q003C000C00034Q003C000D000A4Q0008000B000D000100065B000600C0000100020004693Q00C000010012350004001E4Q003C000500024Q0071000400020002002615000400E40001001F0004693Q00E40001001235000400304Q003C000500024Q00480004000200060004693Q00E200010012350009001F3Q0020620009000900212Q003C000A00034Q006D000B3Q0003001235000C00044Q003C000D00074Q0071000C00020002001052000B0001000C001235000C00044Q003C000D00084Q0071000C0002000200200B000C000C0008001238000E00093Q001238000F00314Q0017000C000F0002001052000B0003000C003014000B000500062Q00080009000B000100065B000400D0000100020004693Q00D000012Q0045000300024Q00433Q00017Q001F3Q0003043Q007479706503063Q00737472696E6703043Q0066696E6403013Q000A034Q0003143Q00526561736F6E206E6F742073706563696669656403063Q00736F7572636503063Q00726561736F6E03023Q00617403023Q006F7303043Q0074696D6503063Q0075736572496403063Q0055736572496403083Q00757365724E616D6503043Q004E616D6503053Q006A6F62496403043Q0067616D6503053Q004A6F62496403073Q00706C616365496403073Q00506C616365496403043Q007761726E031D3Q005B4D415849204855425D204B69636B202F20646973636F2Q6E6563743A03013Q002D03083Q00746F737472696E672Q033Q00737562026Q00F03F026Q006E4003053Q007072696E7403193Q005B4D415849204855425D204B69636B206C6F2Q676564202D3E03043Q007461736B03053Q00737061776E03694Q006500035Q0006210003000400013Q0004693Q000400012Q00433Q00013Q001235000300014Q003C000400014Q007100030002000200261500030013000100020004693Q0013000100200B000300010003001238000500044Q00170003000500020006210003001300013Q0004693Q001300012Q0065000300014Q003C000400014Q007100030002000200061B00010013000100030004693Q001300012Q0065000300024Q003C00046Q003C000500014Q00170003000500020006210003001A00013Q0004693Q001A00012Q00433Q00013Q0006210001001E00013Q0004693Q001E00010026150001001F000100050004693Q001F0001001238000100064Q0057000300014Q006F00036Q006F000100034Q006F3Q00044Q006D00033Q0007001052000300073Q0010520003000800010012350004000A3Q00206200040004000B2Q00240004000100020010520003000900042Q0065000400053Q0006210004003100013Q0004693Q003100012Q0065000400053Q00206200040004000D00064D00040032000100010004693Q003200012Q002E000400043Q0010520003000C00042Q0065000400053Q0006210004003A00013Q0004693Q003A00012Q0065000400053Q00206200040004000F00064D0004003B000100010004693Q003B00012Q002E000400043Q0010520003000E0004001235000400113Q002062000400040012001052000300100004001235000400113Q0020620004000400140010520003001300042Q0065000400064Q003C000500036Q000400020001001235000400153Q001238000500164Q003C00065Q001238000700173Q001235000800184Q003C000900014Q007100080002000200200B000800080019001238000A001A3Q001238000B001B4Q005A0008000B4Q001E00043Q00010012350004001C3Q0012380005001D4Q0065000600074Q00080004000600012Q0065000400084Q00240004000100020006210004005B00013Q0004693Q005B00010026150004005C000100050004693Q005C00012Q00433Q00013Q0012350005001E3Q00206200050005001F00062B00063Q000100082Q00313Q00094Q00293Q00044Q00313Q000A4Q00313Q000B4Q00313Q000C4Q00298Q00293Q00014Q00293Q00026Q0005000200012Q00433Q00013Q00013Q00013Q0003053Q007063612Q6C000C3Q0012353Q00013Q00062B00013Q000100082Q00318Q00313Q00014Q00313Q00024Q00313Q00034Q00313Q00044Q00313Q00054Q00313Q00064Q00313Q00078Q000200012Q00433Q00013Q00013Q00153Q002Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030A3Q004A534F4E456E636F646503063Q00656D6265647303053Q007469746C65030E3Q006B69636B5F6C6F675F7469746C6503053Q00636F6C6F72023Q008087E96C4103063Q006669656C647303063Q00662Q6F74657203043Q0074657874030F3Q006B69636B5F6C6F675F662Q6F74657203093Q0074696D657374616D7003083Q004461746554696D652Q033Q006E6F7703093Q00546F49736F44617465002A4Q00658Q006D00013Q00042Q0065000200013Q0010520001000100020030140001000200032Q006D00023Q00010030140002000500060010520001000400022Q0065000200023Q00200B0002000200082Q006D00043Q00012Q006D000500014Q006D00063Q00052Q0065000700033Q0012380008000B4Q00710007000200020010520006000A00070030140006000C000D2Q0065000700044Q0065000800054Q0065000900064Q0065000A00074Q00170007000A00020010520006000E00072Q006D00073Q00012Q0065000800033Q001238000900114Q00710008000200020010520007001000080010520006000F0007001235000700133Q0020620007000700142Q002400070001000200200B0007000700152Q00710007000200020010520006001200072Q006C0005000100010010520004000900052Q00170002000400020010520001000700026Q000200012Q00433Q00017Q00033Q0003043Q007479706503063Q00737472696E67034Q0002114Q006500026Q003C00036Q003C000400014Q00170002000400020006210002000700013Q0004693Q000700012Q00433Q00013Q001235000200014Q003C000300014Q007100020002000200261500020010000100020004693Q0010000100261200010010000100030004693Q001000012Q006F000100014Q006F3Q00024Q00433Q00017Q00053Q00026Q001840028Q0003053Q007461626C6503063Q00636F6E63617403013Q000A02143Q00064D00010003000100010004693Q00030001001238000100014Q006D00025Q00062B00033Q000100042Q00293Q00014Q00318Q00293Q00024Q00293Q00034Q003C000400034Q003C00055Q001238000600024Q0008000400060001001235000400033Q0020620004000400042Q003C000500023Q001238000600054Q001D000400064Q002000046Q00433Q00013Q00013Q000B3Q002Q033Q0049734103093Q00546578744C6162656C030A3Q005465787442752Q746F6E03073Q0054657874426F7803043Q0054657874034Q0003053Q007461626C6503063Q00696E7365727403063Q00697061697273030B3Q004765744368696C6472656E026Q00F03F022E4Q006500025Q00060500020004000100010004693Q000400012Q00433Q00013Q00200B00023Q0001001238000400024Q001700020004000200064D00020013000100010004693Q0013000100200B00023Q0001001238000400034Q001700020004000200064D00020013000100010004693Q0013000100200B00023Q0001001238000400044Q00170002000400020006210002002200013Q0004693Q0022000100206200023Q00050006210002002200013Q0004693Q0022000100261200020022000100060004693Q002200012Q0065000300014Q003C000400024Q007100030002000200064D00030022000100010004693Q00220001001235000300073Q0020620003000300082Q0065000400024Q003C000500024Q0008000300050001001235000200093Q00200B00033Q000A2Q0009000300044Q006000023Q00040004693Q002B00012Q0065000700034Q003C000800063Q00200A00090001000B2Q000800070009000100065B00020027000100020004693Q002700012Q00433Q00017Q00013Q0003063Q00506172656E74010F4Q003C00015Q0006210001000D00013Q0004693Q000D00012Q006500025Q0006510001000D000100020004693Q000D00010020620002000100012Q006500035Q0006070002000B000100030004693Q000B00012Q0045000100023Q0020620001000100010004693Q000100012Q00453Q00024Q00433Q00017Q000E3Q0003053Q007063612Q6C03073Q004D652Q73616765034Q00030A3Q004775695365727669636503043Q005479706503123Q00436F2Q6E656374696F6E20652Q726F723A2003083Q00746F737472696E6703063Q00697061697273030B3Q004765744368696C6472656E03043Q004E616D6503083Q00436F72654775693A030E3Q0047657444657363656E64616E74732Q033Q0049734103093Q005363722Q656E477569008D3Q0012353Q00013Q00062B00013Q000100012Q00318Q00483Q000200010006213Q003B00013Q0004693Q003B00010006210001003B00013Q0004693Q003B00010020620002000100020006210002001B00013Q0004693Q001B00010020620002000100020026120002001B000100030004693Q001B00012Q0065000200013Q0020620003000100022Q007100020002000200064D0002001B000100010004693Q001B0001001238000200044Q0065000300023Q0020620004000100022Q007100030002000200064D0003001A000100010004693Q001A00010020620003000100022Q0063000200034Q0065000200033Q0020620003000100052Q00710002000200020006210002003B00013Q0004693Q003B00010020620002000100020006210002002900013Q0004693Q0029000100206200020001000200261200020029000100030004693Q0029000100206200020001000200064D0002002E000100010004693Q002E0001001238000200063Q001235000300073Q0020620004000100052Q00710003000200022Q000E0002000200032Q0065000300014Q003C000400024Q007100030002000200064D0003003B000100010004693Q003B0001001238000300044Q0065000400024Q003C000500024Q007100040002000200064D0004003A000100010004693Q003A00012Q003C000400024Q0063000300033Q001235000200084Q0065000300043Q00200B0003000300092Q0009000300044Q006000023Q00040004693Q005E00012Q0065000700053Q00206200080006000A2Q007100070002000200064D0007005E000100010004693Q005E00012Q0065000700063Q00206200080006000A2Q00710007000200020006210007005E00013Q0004693Q005E00012Q0065000700074Q003C000800064Q00710007000200022Q0065000800024Q003C000900074Q00710008000200020026120008005E000100030004693Q005E00012Q0065000900084Q003C000A00083Q002062000B0006000A2Q00170009000B00020006210009005E00013Q0004693Q005E00010012380009000B3Q002062000A0006000A2Q000E00090009000A2Q003C000A00084Q0063000900033Q00065B00020041000100020004693Q00410001001235000200084Q0065000300043Q00200B00030003000C2Q0009000300044Q006000023Q00040004693Q0088000100200B00070006000D0012380009000E4Q00170007000900020006210007008800013Q0004693Q008800012Q0065000700053Q00206200080006000A2Q007100070002000200064D00070088000100010004693Q008800012Q0065000700063Q00206200080006000A2Q00710007000200020006210007008800013Q0004693Q008800012Q0065000700074Q003C000800064Q00710007000200022Q0065000800024Q003C000900074Q007100080002000200261200080088000100030004693Q008800012Q0065000900084Q003C000A00083Q002062000B0006000A2Q00170009000B00020006210009008800013Q0004693Q008800010012380009000B3Q002062000A0006000A2Q000E00090009000A2Q003C000A00084Q0063000900033Q00065B00020066000100020004693Q006600012Q002E000200034Q0063000200034Q00433Q00013Q00013Q00013Q00030F3Q00476574452Q726F724D652Q7361676500054Q00657Q00200B5Q00012Q001D3Q00014Q00208Q00433Q00017Q00043Q0003063Q00506172656E7403043Q004E616D65034Q0003083Q00436F72654775693A014A3Q0006213Q000500013Q0004693Q0005000100206200013Q000100064D00010006000100010004693Q000600012Q00433Q00014Q006500016Q003C00026Q00710001000200020006210001000C00013Q0004693Q000C00012Q00433Q00014Q0065000100014Q003C00026Q00710001000200020006210001001400013Q0004693Q0014000100206200020001000200064D00020015000100010004693Q0015000100206200023Q00022Q0065000300024Q003C000400024Q00710003000200020006210003002000013Q0004693Q002000012Q006500035Q00061B0004001E000100010004693Q001E00012Q003C00048Q0003000200012Q00433Q00014Q0065000300034Q003C000400024Q007100030002000200064D0003002B000100010004693Q002B00012Q0065000300033Q00206200043Q00022Q007100030002000200064D0003002B000100010004693Q002B00012Q00433Q00014Q0065000300043Q00061B0004002F000100010004693Q002F00012Q003C00046Q00710003000200022Q0065000400054Q003C000500034Q007100040002000200261500040036000100030004693Q003600012Q00433Q00014Q0065000500064Q003C000600044Q003C000700024Q001700050007000200064D0005003D000100010004693Q003D00012Q00433Q00014Q0065000500073Q001238000600044Q003C000700024Q000E0006000600072Q003C000700044Q00080005000700012Q0065000500083Q001238000600044Q003C000700024Q000E0006000600072Q003C000700044Q00080005000700012Q00433Q00017Q000A3Q0003063Q00506172656E7403063Q00737472696E6703053Q006C6F77657203043Q004E616D6503043Q0066696E64030B3Q00652Q726F7270726F6D7074026Q00F03F030C3Q00652Q726F726D652Q7361676503043Q007461736B03053Q006465666572012B3Q0006213Q000500013Q0004693Q0005000100206200013Q000100064D00010006000100010004693Q000600012Q00433Q00014Q006500016Q003C00026Q00710001000200020006210001000C00013Q0004693Q000C00012Q00433Q00013Q001235000100023Q00206200010001000300206200023Q00042Q00710001000200022Q0065000200013Q00206200033Q00042Q007100020002000200064D00020021000100010004693Q0021000100200B000200010005001238000400063Q001238000500074Q0057000600014Q001700020006000200064D00020021000100010004693Q0021000100200B000200010005001238000400083Q001238000500074Q0057000600014Q001700020006000200064D00020024000100010004693Q002400012Q00433Q00013Q001235000300093Q00206200030003000A00062B00043Q000100022Q00313Q00024Q00299Q000003000200012Q00433Q00013Q00013Q00033Q0003043Q007461736B03043Q0077616974026Q33C33F00083Q0012353Q00013Q0020625Q0002001238000100038Q000200012Q00658Q0065000100018Q000200012Q00433Q00017Q00083Q0003063Q00747970656F66030E3Q00682Q6F6B6D6574616D6574686F6403083Q0066756E6374696F6E03113Q006765746E616D6563612Q6C6D6574686F64030B3Q006E65772Q636C6F73757265030B3Q004C6F63616C506C6179657203043Q0067616D65030A3Q002Q5F6E616D6563612Q6C00243Q0012353Q00013Q001235000100024Q00713Q000200020026153Q000A000100030004693Q000A00010012353Q00013Q001235000100044Q00713Q000200020026123Q000B000100030004693Q000B00012Q00433Q00013Q0012353Q00053Q00064D3Q000F000100010004693Q000F000100020F8Q006500015Q00064D00010014000100010004693Q001400012Q0065000100013Q00206200010001000600064D00010017000100010004693Q001700012Q00433Q00014Q002E000200023Q001235000300023Q001235000400073Q001238000500084Q003C00065Q00062B00070001000100032Q00293Q00014Q00313Q00024Q00293Q00024Q0009000600074Q003A00033Q00022Q003C000200034Q00433Q00013Q00027Q0001024Q00453Q00024Q00433Q00017Q00073Q0003113Q006765746E616D6563612Q6C6D6574686F6403043Q004B69636B00034Q0003163Q004B69636B28292077697468206E6F206D652Q73616765030B3Q00506C617965723A4B69636B03083Q00746F737472696E6701193Q001235000200014Q00240002000100022Q006500035Q0006073Q0013000100030004693Q0013000100261500020013000100020004693Q001300012Q0019000300043Q0026120003000C000100030004693Q000C00010026150003000D000100040004693Q000D0001001238000300054Q0065000400013Q001238000500063Q001235000600074Q003C000700034Q0009000600074Q001E00043Q00012Q0065000300024Q003C00046Q003300056Q004600036Q002000036Q00433Q00017Q00023Q0003133Q00452Q726F724D652Q736167654368616E67656403073Q00436F2Q6E656374000D4Q00658Q0065000100013Q00206200010001000100200B00010001000200062B00033Q000100052Q00313Q00014Q00313Q00024Q00313Q00034Q00313Q00044Q00313Q00054Q005A000100034Q001E5Q00012Q00433Q00013Q00013Q00073Q0003053Q007063612Q6C03073Q004D652Q7361676503043Q005479706503083Q00746F737472696E67034Q0003123Q00436F2Q6E656374696F6E20652Q726F723A20030A3Q004775695365727669636500473Q0012353Q00013Q00062B00013Q000100012Q00318Q00483Q000200010006213Q000800013Q0004693Q0008000100064D00010009000100010004693Q000900012Q00433Q00013Q0020620002000100020020620003000100030006210003001400013Q0004693Q001400012Q006D00033Q0001001235000400043Q0020620005000100032Q007100040002000200105200030003000400064D00030015000100010004693Q001500012Q002E000300033Q0006210002001900013Q0004693Q0019000100261500020023000100050004693Q002300012Q0065000400013Q0020620005000100032Q00710004000200020006210004002300013Q0004693Q00230001001238000400063Q001235000500043Q0020620006000100032Q00710005000200022Q000E0002000400050006210002003800013Q0004693Q0038000100261200020038000100050004693Q003800012Q0065000400024Q003C000500024Q007100040002000200064D0004002D000100010004693Q002D00012Q003C000400024Q0065000500034Q003C000600044Q00710005000200020006210005004600013Q0004693Q004600012Q0065000500043Q001238000600074Q003C000700044Q003C000800034Q00080005000800010004693Q004600012Q0065000400013Q0020620005000100032Q00710004000200020006210004004600013Q0004693Q004600012Q0065000400043Q001238000500073Q001238000600063Q001235000700043Q0020620008000100032Q00710007000200022Q000E0006000600072Q003C000700034Q00080004000700012Q00433Q00013Q00013Q00013Q00030F3Q00476574452Q726F724D652Q7361676500054Q00657Q00200B5Q00012Q001D3Q00014Q00208Q00433Q00017Q00023Q0003193Q004C6F63616C506C6179657254656C65706F72744661696C656403073Q00436F2Q6E656374000B4Q00658Q0065000100013Q00206200010001000100200B00010001000200062B00033Q000100032Q00313Q00024Q00313Q00034Q00313Q00044Q005A000100034Q001E5Q00012Q00433Q00013Q00013Q00043Q0003083Q00746F737472696E67030F3Q0054656C65706F7274206661696C6564030E3Q0054656C65706F72744661696C656403063Q00526573756C74031B3Q001235000300013Q00061B00040006000100020004693Q0006000100061B00040006000100010004693Q00060001001238000400024Q00710003000200022Q006500046Q003C000500034Q007100040002000200064D00040011000100010004693Q001100012Q0065000400014Q003C000500034Q00710004000200020006210004001A00013Q0004693Q001A00012Q0065000400023Q001238000500034Q003C000600034Q006D00073Q0001001235000800014Q003C000900014Q00710008000200020010520007000400082Q00080004000700012Q00433Q00017Q00023Q00030F3Q0044657363656E64616E74412Q64656403073Q00436F2Q6E65637400113Q00062B5Q000100022Q00318Q00313Q00014Q003C00016Q0065000200026Q0001000200012Q0065000100034Q0065000200023Q00206200020002000100200B00020002000200062B00040001000100032Q00318Q00313Q00044Q00313Q00014Q005A000200044Q001E00013Q00012Q00433Q00013Q00023Q00023Q0003063Q00697061697273030E3Q0047657444657363656E64616E7473011B3Q00064D3Q0003000100010004693Q000300012Q00433Q00013Q001235000100013Q00200B00023Q00022Q0009000200034Q006000013Q00030004693Q000B00012Q006500066Q003C000700056Q00060002000100065B00010008000100020004693Q000800012Q0065000100014Q003C00028Q000100020001001235000100013Q00200B00023Q00022Q0009000200034Q006000013Q00030004693Q001800012Q0065000600014Q003C000700056Q00060002000100065B00010015000100020004693Q001500012Q00433Q00017Q00013Q0003043Q004E616D6501104Q006500016Q003C00026Q00710001000200020006210001000600013Q0004693Q000600012Q00433Q00014Q0065000100013Q00206200023Q00012Q007100010002000200064D0001000C000100010004693Q000C00012Q00433Q00014Q0065000100024Q003C00028Q0001000200012Q00433Q00017Q00053Q0003043Q0067616D65030A3Q0047657453657276696365030A3Q004C6F6753657276696365030A3Q004D652Q736167654F757403073Q00436F2Q6E65637400143Q0012353Q00013Q00200B5Q0002001238000200034Q00173Q000200020006213Q000900013Q0004693Q0009000100206200013Q000400064D0001000A000100010004693Q000A00012Q00433Q00014Q006500015Q00206200023Q000400200B00020002000500062B00043Q000100032Q00313Q00014Q00313Q00024Q00313Q00034Q005A000200044Q001E00013Q00012Q00433Q00013Q00013Q00053Q0003043Q00456E756D030B3Q004D652Q7361676554797065030C3Q004D652Q73616765452Q726F72030E3Q004D652Q736167655761726E696E67030A3Q004C6F6753657276696365021A3Q001235000200013Q0020620002000200020020620002000200030006510001000B000100020004693Q000B0001001235000200013Q0020620002000200020020620002000200040006510001000B000100020004693Q000B00012Q00433Q00014Q006500026Q003C00036Q007100020002000200064D00020011000100010004693Q001100012Q00433Q00014Q0065000200013Q001238000300054Q003C00046Q00080002000400012Q0065000200023Q001238000300054Q003C00046Q00080002000400012Q00433Q00017Q00033Q00030B3Q004C6F63616C506C61796572030E3Q00506C6179657252656D6F76696E6703073Q00436F2Q6E65637400174Q00657Q00064D3Q0005000100010004693Q000500012Q00653Q00013Q0020625Q000100064D3Q0008000100010004693Q000800012Q00433Q00014Q0065000100024Q0065000200013Q00206200020002000200200B00020002000300062B00043Q000100072Q00298Q00313Q00034Q00313Q00044Q00313Q00054Q00313Q00064Q00313Q00074Q00313Q00084Q005A000200044Q001E00013Q00012Q00433Q00013Q00013Q00013Q00030E3Q00506C6179657252656D6F76696E67011F4Q006500015Q0006513Q0004000100010004693Q000400012Q00433Q00014Q0065000100013Q0006210001000800013Q0004693Q000800012Q00433Q00014Q0065000100024Q005D00010001000200064D0002000D000100010004693Q000D00012Q0065000200033Q00064D00010013000100010004693Q001300012Q0065000300043Q00061B00010013000100030004693Q00130001001238000100013Q0006210002001E00013Q0004693Q001E00012Q0065000300054Q003C000400024Q00710003000200020006210003001E00013Q0004693Q001E00012Q0065000300064Q003C000400014Q003C000500024Q00080003000500012Q00433Q00017Q00033Q00028Q0003093Q0048656172746265617403073Q00436F2Q6E656374000F3Q0012383Q00014Q006500016Q0065000200013Q00206200020002000200200B00020002000300062B00043Q000100062Q00298Q00313Q00024Q00313Q00034Q00313Q00044Q00313Q00054Q00313Q00064Q005A000200044Q001E00013Q00012Q00433Q00013Q00013Q00023Q00026Q00F83F028Q00011F4Q006500016Q0004000100014Q006F00016Q006500015Q00267000010007000100010004693Q000700012Q00433Q00013Q001238000100024Q006F00016Q0065000100013Q0006210001000D00013Q0004693Q000D00012Q00433Q00014Q0065000100024Q005D0001000100020006210002001E00013Q0004693Q001E00012Q0065000300034Q003C000400024Q00710003000200020006210003001E00013Q0004693Q001E00012Q0065000300044Q003C000400014Q003C000500024Q00080003000500012Q0065000300054Q003C000400014Q003C000500024Q00080003000500012Q00433Q00017Q00", GetFEnv(), ...);
