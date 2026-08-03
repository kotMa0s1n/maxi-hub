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
										Stk[Inst[2]] = Env[Inst[3]];
									elseif (Enum > 1) then
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
								elseif (Enum <= 4) then
									if (Enum > 3) then
										Stk[Inst[2]] = Inst[3] ~= 0;
									elseif (Stk[Inst[2]] == Stk[Inst[4]]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum == 5) then
									local B = Inst[3];
									local K = Stk[B];
									for Idx = B + 1, Inst[4] do
										K = K .. Stk[Idx];
									end
									Stk[Inst[2]] = K;
								else
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Top));
								end
							elseif (Enum <= 9) then
								if (Enum <= 7) then
									local B = Stk[Inst[4]];
									if not B then
										VIP = VIP + 1;
									else
										Stk[Inst[2]] = B;
										VIP = Inst[3];
									end
								elseif (Enum > 8) then
									if (Stk[Inst[2]] <= Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A = Inst[2];
									local T = Stk[A];
									local B = Inst[3];
									for Idx = 1, B do
										T[Idx] = Stk[A + Idx];
									end
								end
							elseif (Enum <= 11) then
								if (Enum == 10) then
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
									local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
									Top = (Limit + A) - 1;
									local Edx = 0;
									for Idx = A, Top do
										Edx = Edx + 1;
										Stk[Idx] = Results[Edx];
									end
								end
							elseif (Enum == 12) then
								do
									return Stk[Inst[2]];
								end
							else
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 20) then
							if (Enum <= 16) then
								if (Enum <= 14) then
									for Idx = Inst[2], Inst[3] do
										Stk[Idx] = nil;
									end
								elseif (Enum > 15) then
									Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
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
							elseif (Enum <= 18) then
								if (Enum > 17) then
									if (Stk[Inst[2]] == Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									VIP = Inst[3];
								end
							elseif (Enum == 19) then
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							else
								for Idx = Inst[2], Inst[3] do
									Stk[Idx] = nil;
								end
							end
						elseif (Enum <= 23) then
							if (Enum <= 21) then
								do
									return;
								end
							elseif (Enum > 22) then
								local A = Inst[2];
								local B = Stk[Inst[3]];
								Stk[A + 1] = B;
								Stk[A] = B[Inst[4]];
							else
								local A = Inst[2];
								Stk[A] = Stk[A]();
							end
						elseif (Enum <= 25) then
							if (Enum > 24) then
								local A = Inst[2];
								Top = (A + Varargsz) - 1;
								for Idx = A, Top do
									local VA = Vararg[Idx - A];
									Stk[Idx] = VA;
								end
							else
								local A = Inst[2];
								Stk[A] = Stk[A]();
							end
						elseif (Enum > 26) then
							Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
						else
							local A = Inst[2];
							local Results = {Stk[A](Stk[A + 1])};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum <= 41) then
						if (Enum <= 34) then
							if (Enum <= 30) then
								if (Enum <= 28) then
									Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
								elseif (Enum == 29) then
									Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
								else
									local A = Inst[2];
									local B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
								end
							elseif (Enum <= 32) then
								if (Enum > 31) then
									if (Stk[Inst[2]] < Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif not Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 33) then
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							else
								Stk[Inst[2]] = Stk[Inst[3]];
							end
						elseif (Enum <= 37) then
							if (Enum <= 35) then
								local A = Inst[2];
								do
									return Stk[A], Stk[A + 1];
								end
							elseif (Enum == 36) then
								local A = Inst[2];
								do
									return Unpack(Stk, A, A + Inst[3]);
								end
							else
								Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
							end
						elseif (Enum <= 39) then
							if (Enum == 38) then
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
						elseif (Enum > 40) then
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Inst[3]));
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
					elseif (Enum <= 48) then
						if (Enum <= 44) then
							if (Enum <= 42) then
								if (Stk[Inst[2]] ~= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 43) then
								if (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
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
									if (Mvm[1] == 33) then
										Indexes[Idx - 1] = {Stk,Mvm[3]};
									else
										Indexes[Idx - 1] = {Upvalues,Mvm[3]};
									end
									Lupvals[#Lupvals + 1] = Indexes;
								end
								Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
							end
						elseif (Enum <= 46) then
							if (Enum == 45) then
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
							else
								local A = Inst[2];
								do
									return Stk[A], Stk[A + 1];
								end
							end
						elseif (Enum == 47) then
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Top));
							end
						else
							local A = Inst[2];
							Stk[A](Stk[A + 1]);
						end
					elseif (Enum <= 52) then
						if (Enum <= 50) then
							if (Enum == 49) then
								local A = Inst[2];
								local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Top));
							end
						elseif (Enum == 51) then
							if (Stk[Inst[2]] ~= Inst[4]) then
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
					elseif (Enum <= 54) then
						if (Enum == 53) then
							local A = Inst[2];
							local T = Stk[A];
							for Idx = A + 1, Inst[3] do
								Insert(T, Stk[Idx]);
							end
						else
							Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
						end
					elseif (Enum == 55) then
						local A = Inst[2];
						local Results, Limit = _R(Stk[A](Stk[A + 1]));
						Top = (Limit + A) - 1;
						local Edx = 0;
						for Idx = A, Top do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					else
						Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
					end
				elseif (Enum <= 84) then
					if (Enum <= 70) then
						if (Enum <= 63) then
							if (Enum <= 59) then
								if (Enum <= 57) then
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
										if (Mvm[1] == 33) then
											Indexes[Idx - 1] = {Stk,Mvm[3]};
										else
											Indexes[Idx - 1] = {Upvalues,Mvm[3]};
										end
										Lupvals[#Lupvals + 1] = Indexes;
									end
									Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
								elseif (Enum == 58) then
									Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
								else
									Upvalues[Inst[3]] = Stk[Inst[2]];
								end
							elseif (Enum <= 61) then
								if (Enum > 60) then
									do
										return Stk[Inst[2]];
									end
								else
									VIP = Inst[3];
								end
							elseif (Enum > 62) then
								local A = Inst[2];
								local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 66) then
							if (Enum <= 64) then
								local A = Inst[2];
								do
									return Unpack(Stk, A, Top);
								end
							elseif (Enum == 65) then
								Stk[Inst[2]] = {};
							elseif Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 68) then
							if (Enum > 67) then
								Stk[Inst[2]] = Inst[3] ~= 0;
								VIP = VIP + 1;
							else
								Stk[Inst[2]] = Stk[Inst[3]] + Stk[Inst[4]];
							end
						elseif (Enum > 69) then
							local A = Inst[2];
							local T = Stk[A];
							local B = Inst[3];
							for Idx = 1, B do
								T[Idx] = Stk[A + Idx];
							end
						else
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Top))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum <= 77) then
						if (Enum <= 73) then
							if (Enum <= 71) then
								Stk[Inst[2]] = Upvalues[Inst[3]];
							elseif (Enum > 72) then
								Stk[Inst[2]] = #Stk[Inst[3]];
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
						elseif (Enum <= 75) then
							if (Enum == 74) then
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
								Stk[Inst[2]] = #Stk[Inst[3]];
							end
						elseif (Enum == 76) then
							if (Stk[Inst[2]] ~= Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							Stk[Inst[2]] = Env[Inst[3]];
						end
					elseif (Enum <= 80) then
						if (Enum <= 78) then
							Stk[Inst[2]] = {};
						elseif (Enum == 79) then
							Stk[Inst[2]] = Upvalues[Inst[3]];
						elseif (Stk[Inst[2]] ~= Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 82) then
						if (Enum > 81) then
							if (Stk[Inst[2]] < Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							Stk[Inst[2]] = Inst[3] ~= 0;
						end
					elseif (Enum > 83) then
						local A = Inst[2];
						local Results = {Stk[A](Stk[A + 1])};
						local Edx = 0;
						for Idx = A, Inst[4] do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					else
						local A = Inst[2];
						local B = Inst[3];
						for Idx = A, B do
							Stk[Idx] = Vararg[Idx - A];
						end
					end
				elseif (Enum <= 98) then
					if (Enum <= 91) then
						if (Enum <= 87) then
							if (Enum <= 85) then
								if Stk[Inst[2]] then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum > 86) then
								if (Stk[Inst[2]] <= Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A = Inst[2];
								Stk[A](Stk[A + 1]);
							end
						elseif (Enum <= 89) then
							if (Enum == 88) then
								local A = Inst[2];
								Stk[A] = Stk[A](Stk[A + 1]);
							else
								Stk[Inst[2]] = Stk[Inst[3]];
							end
						elseif (Enum == 90) then
							local A = Inst[2];
							do
								return Unpack(Stk, A, Top);
							end
						elseif (Stk[Inst[2]] < Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum <= 94) then
						if (Enum <= 92) then
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 93) then
							local A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
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
					elseif (Enum <= 96) then
						if (Enum == 95) then
							Stk[Inst[2]][Inst[3]] = Inst[4];
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
					elseif (Enum > 97) then
						local A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
					else
						local A = Inst[2];
						Top = (A + Varargsz) - 1;
						for Idx = A, Top do
							local VA = Vararg[Idx - A];
							Stk[Idx] = VA;
						end
					end
				elseif (Enum <= 105) then
					if (Enum <= 101) then
						if (Enum <= 99) then
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						elseif (Enum > 100) then
							local A = Inst[2];
							local B = Inst[3];
							for Idx = A, B do
								Stk[Idx] = Vararg[Idx - A];
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
					elseif (Enum <= 103) then
						if (Enum == 102) then
							Stk[Inst[2]] = Inst[3] ~= 0;
							VIP = VIP + 1;
						else
							Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
						end
					elseif (Enum == 104) then
						local A = Inst[2];
						Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
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
				elseif (Enum <= 109) then
					if (Enum <= 107) then
						if (Enum == 106) then
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						else
							local A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Inst[3]));
						end
					elseif (Enum == 108) then
						local A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Inst[3]));
					elseif not Stk[Inst[2]] then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 111) then
					if (Enum > 110) then
						local A = Inst[2];
						do
							return Stk[A](Unpack(Stk, A + 1, Top));
						end
					else
						Upvalues[Inst[3]] = Stk[Inst[2]];
					end
				elseif (Enum > 112) then
					if (Stk[Inst[2]] < Stk[Inst[4]]) then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				else
					Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!5D3Q0003063Q00747970656F6603073Q0067657467656E7603083Q0066756E6374696F6E03023Q005F47030E3Q004D617869487562536B69704B65792Q01030F3Q005F4D617869487562417574684C6962031A3Q006D6178692D6875622F6D6178692D6875622D617574682E6C756103113Q006D6178692D6875622D617574682E6C756103043Q007479706503103Q004D6178694875624C6F63616C522Q6F7403063Q00737472696E67034Q0003053Q007461626C6503063Q00696E73657274026Q00F03F03123Q002F6D6178692D6875622D617574682E6C756103083Q007265616466696C6503063Q00697366696C6503063Q0069706169727303123Q004D6178694875624F2Q66696369616C52617703113Q004D61786948756252656D6F74654261736503043Q0067616D6503073Q00482Q747047657403053Q007063612Q6C03053Q00652Q726F72032B3Q005B4D415849204855425D204D692Q73696E67206D6178692D6875622D617574682E6C756120286B69636B29030A3Q006C6F6164737472696E6703123Q00406D6178692D6875622D617574682E6C756103193Q005B4D415849204855425D206175746820636F6D70696C653A2003083Q00746F737472696E6703113Q005B4D415849204855425D20617574683A2003053Q00677561726403043Q006B69636B030A3Q0047657453657276696365030B3Q00482Q74705365727669636503073Q00506C6179657273030A3Q0047756953657276696365030F3Q0054656C65706F72745365727669636503073Q00436F7265477569030A3Q0052756E5365727669636503193Q0068656164736574646973636F2Q6E656374652Q6469616C6F6703133Q0068656164736574646973636F2Q6E6563746564030F3Q00762Q72656D6F76616C6469616C6F6703093Q00726F626C6F7867756903043Q0063686174030A3Q00706C617965726C697374030A3Q00656D6F7465736D656E7503083Q006261636B7061636B030A3Q007374617274657267756903053Q006C6162656C03023Q006F6B03063Q00612Q6365707403073Q006465636C696E6503063Q0063616E63656C03053Q00636C6F73652Q033Q0079657303023Q006E6F03073Q00672Q6F646279652Q033Q003Q2E03093Q005E726573746172742403143Q006865616473657420646973636F2Q6E656374656403163Q00706C6561736520726573746172742074686520612Q7003233Q00746F20636F6E74696E756520706C6179696E672C20706C65617365207265737461727403153Q00747269616E676C65252D6578636C616D6174696F6E03143Q00747269616E676C65206578636C616D6174696F6E03063Q006B69636B656403063Q0062612Q6E65642Q033Q0062616E030A3Q00646973636F2Q6E656374030C3Q00646973636F2Q6E656374656403073Q0072656D6F76656403083Q00657870652Q6C656403093Q006D6F64657261746F72030A3Q006D6F6465726174696F6E03093Q0076696F6C6174696F6E03053Q00636865617403073Q006578706C6F6974030A3Q007465726D696E6174656403093Q0073757370656E64656403063Q00D0BAD0B8D0BA030A3Q00D0BAD0B8D0BAD0BDD18303063Q00D0B1D0B0D0BD030A3Q00D0B7D0B0D0B1D0B0D0BD030C3Q00D0BED182D0BAD0BBD18ED187030C3Q00D183D0B4D0B0D0BBD0B5D0BD03123Q00D0BCD0BED0B4D0B5D180D0B0D182D0BED180030B3Q00652Q726F7270726F6D7074030C3Q00652Q726F726D652Q7361676503093Q006C6561766567616D65030D3Q00636F6E6669726D6469616C6F67030D3Q00756E6976657273616C636F726503053Q007374617274002Q012Q00124Q00013Q00122Q000100024Q00623Q0002000200265C3Q0009000100030004113Q0009000100124Q00024Q00183Q0001000200061F3Q000A000100010004113Q000A000100124Q00043Q00203A00013Q000500263300010077000100060004113Q0077000100203A00013Q000700061F00010074000100010004113Q007400012Q0014000200024Q0041000300023Q00123E000400083Q00123E000500094Q000800030002000100122Q0004000A3Q00203A00053Q000B2Q006200040002000200265C000400250001000C0004113Q0025000100203A00043Q000B002633000400250001000D0004113Q0025000100122Q0004000E3Q00203A00040004000F2Q0059000500033Q00123E000600103Q00203A00073Q000B00123E000800114Q00020007000700082Q006C00040007000100122Q000400013Q00122Q000500124Q006200040002000200265C0004003F000100030004113Q003F000100122Q000400013Q00122Q000500134Q006200040002000200265C0004003F000100030004113Q003F000100122Q000400144Q0059000500034Q00540004000200060004113Q003D000100122Q000900134Q0059000A00084Q00620009000200020006420009003D00013Q0004113Q003D000100122Q000900124Q0059000A00084Q00620009000200022Q0059000200093Q0004113Q003F000100066000040033000100020004113Q0033000100061F00020053000100010004113Q0053000100203A00043Q001500061F00040045000100010004113Q0045000100203A00043Q00160006420004005200013Q0004113Q0052000100122Q000500013Q00122Q000600173Q00203A0006000600182Q006200050002000200265C00050052000100030004113Q0052000100122Q000500193Q00062B00063Q000100022Q00213Q00024Q00213Q00044Q00560005000200012Q004A00045Q00061F00020058000100010004113Q0058000100122Q0004001A3Q00123E0005001B4Q005600040002000100122Q0004001C4Q0059000500023Q00123E0006001D4Q006300040006000500061F00040065000100010004113Q0065000100122Q0006001A3Q00123E0007001E3Q00122Q0008001F4Q0059000900054Q00620008000200022Q00020007000700082Q005600060002000100122Q000600194Q0059000700044Q005400060002000700061F00060071000100010004113Q0071000100122Q0008001A3Q00123E000900203Q00122Q000A001F4Q0059000B00074Q0062000A000200022Q000200090009000A2Q00560008000200012Q0059000100073Q0010223Q000700012Q004A00025Q00203A00020001002100123E000300224Q005600020002000100124Q00173Q00201E5Q002300123E000200244Q00683Q0002000200122Q000100173Q00201E00010001002300123E000300254Q006800010003000200122Q000200173Q00201E00020002002300123E000400264Q006800020004000200122Q000300173Q00201E00030003002300123E000500274Q006800030005000200122Q000400173Q00201E00040004002300123E000600284Q006800040006000200122Q000500173Q00201E00050005002300123E000700294Q00680005000700022Q004100066Q004100073Q000900305F0007002A000600305F0007002B000600305F0007002C000600305F0007002D000600305F0007002E000600305F0007002F000600305F00070030000600305F00070031000600305F0007003200062Q004100083Q000A00305F00080033000600305F00080034000600305F00080035000600305F00080036000600305F00080037000600305F00080038000600305F00080039000600305F0008003A000600305F0008003B000600305F0008003C00062Q0041000900063Q00123E000A003D3Q00123E000B003E3Q00123E000C003F3Q00123E000D00403Q00123E000E00413Q00123E000F00424Q00080009000600012Q0041000A00133Q00123E000B00223Q00123E000C00433Q00123E000D00443Q00123E000E00453Q00123E000F00463Q00123E001000473Q00123E001100483Q00123E001200493Q00123E0013004A3Q00123E0014004B3Q00123E0015004C3Q00123E0016004D3Q00123E0017004E3Q00123E0018004F3Q00123E001900503Q00123E001A00513Q00123E001B00523Q00123E001C00533Q00123E001D00543Q00123E001E00553Q00123E001F00563Q00123E002000574Q0008000A001600012Q0041000B00083Q00123E000C00583Q00123E000D00593Q00123E000E00463Q00123E000F00223Q00123E001000453Q00123E0011005A3Q00123E0012005B3Q00123E0013005C4Q0008000B0008000100021B000C00013Q00062B000D0002000100022Q00213Q000C4Q00213Q00093Q00062B000E0003000100012Q00213Q000D3Q00062B000F0004000100012Q00213Q00073Q00062B00100005000100022Q00213Q000C4Q00213Q00083Q00062B00110006000100022Q00213Q000F4Q00213Q000E3Q00062B00120007000100012Q00213Q000B3Q00062B00130008000100012Q00213Q000A3Q00062B00140009000100032Q00213Q00104Q00213Q000D4Q00213Q00133Q00062B0015000A000100022Q00213Q00114Q00213Q00123Q00021B0016000B3Q00062B0017000C000100012Q00213Q000F3Q00021B0018000D3Q00062B0019000E000100112Q00213Q00014Q00213Q00184Q00218Q00213Q00144Q00213Q00114Q00213Q00104Q00213Q00044Q00213Q00024Q00213Q000E4Q00213Q00164Q00213Q000F4Q00213Q00124Q00213Q00154Q00213Q00174Q00213Q00034Q00213Q00134Q00213Q00053Q0010220006005D00192Q000C000600024Q00013Q00013Q000F3Q00063Q0003043Q0067616D6503073Q00482Q747047657403143Q006D6178692D6875622D617574682E6C75613F763D03083Q00746F737472696E6703023Q006F7303043Q0074696D65000E3Q00124Q00013Q00201E5Q00022Q004F000200013Q00123E000300033Q00122Q000400043Q00122Q000500053Q00203A0005000500062Q000A000500014Q005D00043Q00022Q00020002000200042Q0004000300014Q00683Q000300022Q006E8Q00013Q00017Q00073Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203043Q006773756203043Q005E25732B03043Q0025732B2401143Q00122Q000100014Q005900026Q006200010002000200263300010007000100020004113Q0007000100123E000100034Q000C000100023Q00122Q000100023Q00203A00010001000400201E00023Q000500123E000400063Q00123E000500034Q006800020005000200201E00020002000500123E000400073Q00123E000500034Q0069000200054Q006F00016Q005A00016Q00013Q00017Q00053Q00034Q0003063Q0069706169727303043Q0066696E64026Q00F03F03053Q006D61746368011E4Q004F00016Q005900026Q006200010002000200265C00010007000100010004113Q000700012Q0004000200014Q000C000200023Q00122Q000200024Q004F000300014Q00540002000200040004113Q0019000100201E0007000100032Q0059000900063Q00123E000A00044Q0004000B00014Q00680007000B000200061F00070017000100010004113Q0017000100201E0007000100052Q0059000900064Q00680007000900020006420007001900013Q0004113Q001900012Q0004000700014Q000C000700023Q0006600002000B000100020004113Q000B00012Q000400026Q000C000200024Q00013Q00017Q00083Q0003043Q007479706503063Q00737472696E67034Q0003063Q00676D6174636803063Q005B5E0D0A5D2B03043Q006773756203043Q005E25732B03043Q0025732B2401243Q00122Q000100014Q005900026Q006200010002000200265C00010007000100020004113Q0007000100265C3Q0009000100030004113Q000900012Q000400016Q000C000100024Q000400015Q00201E00023Q000400123E000400054Q00630002000400040004113Q0020000100201E00060005000600123E000800073Q00123E000900034Q006800060009000200201E00060006000600123E000800083Q00123E000900034Q006800060009000200263300060020000100030004113Q002000012Q0004000100014Q004F00076Q0059000800064Q006200070002000200061F00070020000100010004113Q002000012Q000400076Q000C000700023Q0006600002000E000100010004113Q000E00012Q000C000100024Q00013Q00017Q00083Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203043Q0066696E6403133Q0068656164736574646973636F2Q6E6563746564026Q00F03F00011E3Q00122Q000100014Q005900026Q006200010002000200265C00010007000100020004113Q0007000100265C3Q0009000100030004113Q000900012Q000400016Q000C000100023Q00122Q000100023Q00203A0001000100042Q005900026Q00620001000200022Q004F00026Q00700002000200010006420002001300013Q0004113Q001300012Q0004000200014Q000C000200023Q00201E00020001000500123E000400063Q00123E000500074Q0004000600014Q006800020006000200265C0002001B000100080004113Q001B00012Q004400026Q0004000200014Q000C000200024Q00013Q00017Q00023Q00034Q00027Q004001154Q004F00016Q005900026Q006200010002000200265C00010007000100010004113Q000700012Q0004000200014Q000C000200024Q004F000200014Q00700002000200010006420002000D00013Q0004113Q000D00012Q0004000200014Q000C000200024Q0049000200013Q00260900020012000100020004113Q001200012Q0004000200014Q000C000200024Q000400026Q000C000200024Q00013Q00017Q00073Q0003063Q00737472696E6703053Q006C6F77657203083Q00746F737472696E67034Q0003043Q0066696E6403133Q0068656164736574646973636F2Q6E6563746564026Q00F03F03224Q004F00036Q0059000400024Q00620003000200020006420003000700013Q0004113Q000700012Q0004000300014Q000C000300024Q004F000300014Q0059000400014Q00620003000200020006420003000E00013Q0004113Q000E00012Q0004000300014Q000C000300023Q00122Q000300013Q00203A00030003000200122Q000400033Q0006070005001400013Q0004113Q0014000100123E000500044Q000F000400054Q005D00033Q000200201E00040003000500123E000600063Q00123E000700074Q0004000800014Q00680004000800020006420004001F00013Q0004113Q001F00012Q0004000400014Q000C000400024Q000400046Q000C000400024Q00013Q00017Q00073Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203063Q0069706169727303043Q0066696E64026Q00F03F011F3Q00122Q000100014Q005900026Q006200010002000200265C00010007000100020004113Q0007000100265C3Q0009000100030004113Q000900012Q000400016Q000C000100023Q00122Q000100023Q00203A0001000100042Q005900026Q006200010002000200122Q000200054Q004F00036Q00540002000200040004113Q001A000100201E0007000100062Q0059000900063Q00123E000A00074Q0004000B00014Q00680007000B00020006420007001A00013Q0004113Q001A00012Q0004000700014Q000C000700023Q00066000020011000100020004113Q001100012Q000400026Q000C000200024Q00013Q00017Q00073Q0003043Q007479706503063Q00737472696E67034Q0003053Q006C6F77657203063Q0069706169727303043Q0066696E64026Q00F03F01213Q00122Q000100014Q005900026Q006200010002000200265C00010007000100020004113Q0007000100265C3Q0009000100030004113Q000900012Q000400016Q000C000100023Q00122Q000100023Q00203A0001000100042Q005900026Q006200010002000200122Q000200054Q004F00036Q00540002000200040004113Q001C000100122Q000700023Q00203A0007000700062Q0059000800014Q0059000900063Q00123E000A00074Q0004000B00014Q00680007000B00020006420007001C00013Q0004113Q001C00012Q0004000700014Q000C000700023Q00066000020011000100020004113Q001100012Q000400026Q000C000200024Q00013Q00017Q000A3Q0003043Q007479706503063Q00737472696E67034Q00026Q00F0BF03063Q00676D6174636803063Q005B5E0D0A5D2B03043Q006773756203043Q005E25732B03043Q0025732B24026Q00694001523Q00122Q000100014Q005900026Q006200010002000200265C00010007000100020004113Q0007000100265C3Q0009000100030004113Q0009000100123E000100034Q000C000100023Q00123E000100033Q00123E000200043Q00201E00033Q000500123E000500064Q00630003000500050004113Q002F000100201E00070006000700123E000900083Q00123E000A00034Q00680007000A000200201E00070007000700123E000900093Q00123E000A00034Q00680007000A00020026330007002F000100030004113Q002F00012Q004F00086Q0059000900074Q006200080002000200061F0008002F000100010004113Q002F00012Q004F000800014Q0059000900074Q00620008000200020006420008002400013Q0004113Q002400010004113Q002F00012Q0049000800074Q004F000900024Q0059000A00074Q00620009000200020006420009002B00013Q0004113Q002B000100201C00080008000A0006710002002F000100080004113Q002F00012Q0059000200084Q0059000100073Q0006600003000F000100010004113Q000F000100263300010034000100030004113Q003400012Q000C000100023Q00201E00033Q000500123E000500064Q00630003000500050004113Q004D000100201E00070006000700123E000900083Q00123E000A00034Q00680007000A000200201E00070007000700123E000900093Q00123E000A00034Q00680007000A00020026330007004D000100030004113Q004D00012Q004F00086Q0059000900074Q006200080002000200061F0008004D000100010004113Q004D00012Q004F000800014Q0059000900074Q006200080002000200061F0008004D000100010004113Q004D00012Q000C000700023Q00066000030038000100010004113Q0038000100123E000300034Q000C000300024Q00013Q00017Q00033Q0003043Q007479706503063Q00737472696E67034Q0002174Q004F00026Q0014000300034Q005900046Q0059000500014Q00680002000500020006420002000900013Q0004113Q000900012Q000400026Q000C000200023Q00122Q000200014Q005900036Q006200020002000200265C00020012000100020004113Q001200010026333Q0012000100030004113Q001200012Q0004000200014Q000C000200024Q004F000200014Q0059000300014Q0029000200034Q005A00026Q00013Q00017Q00093Q0003063Q00747970656F6603083Q00456E756D4974656D03083Q00746F737472696E6703083Q00456E756D54797065030F3Q00436F2Q6E656374696F6E452Q726F7203043Q00456E756D03103Q00446973636F2Q6E656374452Q726F727303113Q00506C6163656C61756E6368452Q726F7273030E3Q0054656C65706F7274452Q726F727301213Q00122Q000100014Q005900026Q006200010002000200263300010007000100020004113Q000700012Q000400016Q000C000100023Q00122Q000100033Q00203A00023Q00042Q006200010002000200265C0001000E000100050004113Q000E00012Q0004000200014Q000C000200023Q00122Q000200063Q00203A00020002000500203A0002000200070006503Q001E000100020004113Q001E000100122Q000200063Q00203A00020002000500203A0002000200080006503Q001E000100020004113Q001E000100122Q000200063Q00203A00020002000500203A0002000200090006503Q001E000100020004113Q001E00012Q004400026Q0004000200014Q000C000200024Q00013Q00017Q00023Q0003043Q004E616D6503053Q007063612Q6C01123Q00061F3Q0004000100010004113Q000400012Q000400016Q000C000100024Q004F00015Q00203A00023Q00012Q00620001000200020006420001000F00013Q0004113Q000F000100122Q000100023Q00062B00023Q000100012Q00218Q00560001000200012Q0004000100014Q000C000100024Q000400016Q000C000100024Q00013Q00013Q00013Q00013Q0003073Q0044657374726F7900044Q004F7Q00201E5Q00012Q00563Q000200012Q00013Q00017Q00053Q0003063Q00747970656F6603073Q007265717565737403083Q0066756E6374696F6E2Q033Q0073796E03043Q00682Q747001243Q00122Q000100013Q00122Q000200024Q006200010002000200265C00010009000100030004113Q0009000100122Q000100024Q005900026Q0029000100024Q005A00015Q00122Q000100043Q0006420001001500013Q0004113Q0015000100122Q000100043Q00203A0001000100020006420001001500013Q0004113Q0015000100122Q000100043Q00203A0001000100022Q005900026Q0029000100024Q005A00015Q00122Q000100053Q0006420001002100013Q0004113Q0021000100122Q000100053Q00203A0001000100020006420001002100013Q0004113Q0021000100122Q000100053Q00203A0001000100022Q005900026Q0029000100024Q005A00016Q0014000100014Q000C000100024Q00013Q00017Q000D3Q00030A3Q00676574576562682Q6F6B03083Q006765745374617473030E3Q0067657445787472614669656C647303073Q006C6F6746696C6503173Q006D6178692D6875622D6C6173742D6B69636B2E6A736F6E03063Q00706C61796572030B3Q004C6F63616C506C61796572030B3Q00682Q74705265717565737403063Q007265706F727403043Q0073746F7003053Q007063612Q6C03053Q007072696E74031E3Q005B4D415849204855425D204B69636B206D6F6E69746F722061637469766501A63Q00061F3Q0004000100010004113Q000400012Q004100016Q00593Q00013Q00203A00013Q000100203A00023Q000200203A00033Q000300203A00043Q000400061F0004000B000100010004113Q000B000100123E000400053Q00203A00053Q000600061F00050010000100010004113Q001000012Q004F00055Q00203A00050005000700203A00063Q000800061F00060014000100010004113Q001400012Q004F000600013Q00062B00073Q000100022Q00213Q00014Q00218Q000400086Q004100096Q0004000A6Q0014000B000C3Q00062B000D0001000100012Q00213Q00093Q00062B000E0002000100012Q00213Q00093Q00062B000F0003000100022Q00213Q00044Q00473Q00023Q00062B00100004000100032Q00213Q00054Q00213Q00024Q00213Q00033Q00062B001100050001000C2Q00213Q000A4Q00473Q00034Q00473Q00044Q00213Q000B4Q00213Q000C4Q00213Q00054Q00213Q000F4Q00213Q00044Q00213Q00074Q00213Q00064Q00473Q00024Q00213Q00103Q00062B00120006000100032Q00473Q00044Q00213Q000B4Q00213Q000C3Q00062B00130007000100012Q00473Q00053Q00062B00140008000100012Q00473Q00063Q00062B00150009000100092Q00473Q00074Q00473Q00084Q00473Q00034Q00473Q00094Q00473Q00064Q00473Q000A4Q00473Q000B4Q00213Q00134Q00473Q000C3Q00062B0016000A000100092Q00473Q000D4Q00213Q00144Q00473Q000A4Q00473Q000B4Q00213Q00134Q00473Q00034Q00473Q000C4Q00213Q00124Q00213Q00113Q00062B0017000B000100032Q00473Q000D4Q00473Q000B4Q00213Q00163Q00062B0018000C000100032Q00213Q00054Q00478Q00213Q00113Q00062B0019000D000100062Q00213Q000D4Q00473Q00074Q00473Q00094Q00473Q00034Q00473Q000C4Q00213Q00113Q00062B001A000E000100052Q00213Q000D4Q00473Q000E4Q00473Q000C4Q00473Q000F4Q00213Q00113Q00062B001B000F000100052Q00473Q000D4Q00213Q00174Q00473Q00064Q00213Q000D4Q00473Q000B3Q00062B001C0010000100052Q00213Q000D4Q00473Q000C4Q00473Q000F4Q00213Q00124Q00213Q00113Q00062B001D0011000100092Q00213Q00054Q00478Q00213Q000D4Q00213Q000A4Q00213Q00154Q00213Q000B4Q00213Q000C4Q00473Q000C4Q00213Q00113Q00062B001E0012000100072Q00213Q000D4Q00473Q00104Q00213Q000A4Q00213Q00154Q00473Q000C4Q00213Q00124Q00213Q00113Q0006420008008800013Q0004113Q008800012Q0041001F3Q0002001022001F00090011001022001F000A000E2Q000C001F00024Q0004000800013Q00122Q001F000B4Q0059002000184Q0056001F0002000100122Q001F000B4Q0059002000194Q0056001F0002000100122Q001F000B4Q00590020001A4Q0056001F0002000100122Q001F000B4Q00590020001B4Q0056001F0002000100122Q001F000B4Q00590020001C4Q0056001F0002000100122Q001F000B4Q00590020001D4Q0056001F0002000100122Q001F000B4Q00590020001E4Q0056001F0002000100122Q001F000C3Q00123E0020000D4Q0056001F000200012Q0041001F3Q0002001022001F00090011001022001F000A000E2Q000C001F00024Q00013Q00013Q00133Q000A3Q0003063Q00747970656F6603083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503063Q00737472696E6703043Q006773756203043Q005E25732B034Q0003043Q0025732B2403073Q00776562682Q6F6B00313Q00124Q00014Q004F00016Q00623Q0002000200265C3Q001B000100020004113Q001B000100124Q00034Q004F00016Q00543Q000200010006423Q001B00013Q0004113Q001B000100122Q000200044Q0059000300014Q006200020002000200265C0002001B000100050004113Q001B000100201E00020001000600123E000400073Q00123E000500084Q006800020005000200201E00020002000600123E000400093Q00123E000500084Q00680002000500022Q0059000100023Q0026330001001B000100080004113Q001B00012Q000C000100024Q004F3Q00013Q00203A5Q000A00061F3Q0020000100010004113Q0020000100123E3Q00083Q00122Q000100044Q005900026Q006200010002000200265C0001002E000100050004113Q002E000100201E00013Q000600123E000300073Q00123E000400084Q006800010004000200201E00010001000600123E000300093Q00123E000400084Q0029000100044Q005A00015Q00123E000100084Q000C000100024Q00013Q00017Q00023Q0003053Q007461626C6503063Q00696E7365727401083Q0006423Q000700013Q0004113Q0007000100122Q000100013Q00203A0001000100022Q004F00026Q005900036Q006C0001000300012Q00013Q00017Q00043Q0003063Q0069706169727303053Q007063612Q6C03053Q007461626C6503053Q00636C65617200103Q00124Q00014Q004F00016Q00543Q000200020004113Q0009000100122Q000500023Q00062B00063Q000100012Q00213Q00044Q00560005000200012Q004A00035Q0006603Q0004000100020004113Q0004000100124Q00033Q00203A5Q00042Q004F00016Q00563Q000200012Q00013Q00013Q00013Q00013Q00030A3Q00446973636F2Q6E65637400044Q004F7Q00201E5Q00012Q00563Q000200012Q00013Q00017Q00043Q0003063Q00747970656F6603093Q00777269746566696C6503083Q0066756E6374696F6E03053Q007063612Q6C010D3Q00122Q000100013Q00122Q000200024Q006200010002000200263300010006000100030004113Q000600012Q00013Q00013Q00122Q000100043Q00062B00023Q000100032Q00478Q00473Q00014Q00218Q00560001000200012Q00013Q00013Q00013Q00023Q0003093Q00777269746566696C65030A3Q004A534F4E456E636F646500083Q00124Q00014Q004F00016Q004F000200013Q00201E0002000200022Q004F000400024Q0069000200044Q00065Q00012Q00013Q00017Q002D3Q0003043Q006E616D6503063Q00536F7572636503053Q0076616C756503083Q00746F737472696E6703063Q00696E6C696E652Q0103063Q00526561736F6E2Q033Q00737562026Q00F03F025Q00208C40010003063Q00506C6179657203043Q004E616D652Q033Q0020286003063Q0055736572496403023Q00602903013Q003F03073Q00506C616365496403043Q0067616D6503053Q004A6F62496403043Q0054696D6503023Q006F7303043Q006461746503113Q0025592D256D2D25642025483A254D3A255303063Q00747970656F6603083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503053Q007461626C6503053Q00706861736503063Q00696E73657274030A3Q004661726D207068617365030A3Q0074722Q65734D696E6564030B3Q0073746F6E65734D696E656403073Q0053652Q73696F6E03063Q00737472696E6703063Q00666F726D617403123Q0074722Q65733A25732073746F6E65733A2573028Q00030B3Q006661726D5365636F6E647303093Q004661726D2074696D6503013Q007303063Q0069706169727303053Q007061697273026Q00694003C14Q0041000300064Q004100043Q000300305F00040001000200122Q000500044Q005900066Q006200050002000200102200040003000500305F0004000500062Q004100053Q000300305F00050001000700122Q000600044Q0059000700014Q006200060002000200201E00060006000800123E000800093Q00123E0009000A4Q006800060009000200102200050003000600305F00050005000B2Q004100063Q000300305F00060001000C2Q004F00075Q0006420007002100013Q0004113Q002100012Q004F00075Q00203A00070007000D00123E0008000E4Q004F00095Q00203A00090009000F00123E000A00104Q000200070007000A00061F00070022000100010004113Q0022000100123E000700113Q00102200060003000700305F00060005000B2Q004100073Q000300305F00070001001200122Q000800043Q00122Q000900133Q00203A0009000900122Q006200080002000200102200070003000800305F0007000500062Q004100083Q000300305F00080001001400122Q000900043Q00122Q000A00133Q00203A000A000A00142Q006200090002000200102200080003000900305F0008000500062Q004100093Q000300305F00090001001500122Q000A00163Q00203A000A000A001700123E000B00184Q0062000A0002000200102200090003000A00305F0009000500062Q000800030006000100122Q000400194Q004F000500014Q006200040002000200265C000400880001001A0004113Q0088000100122Q0004001B4Q004F000500014Q00540004000200050006420004008800013Q0004113Q0088000100122Q0006001C4Q0059000700054Q006200060002000200265C000600880001001D0004113Q0088000100203A00060005001E0006420006005A00013Q0004113Q005A000100122Q0006001D3Q00203A00060006001F2Q0059000700034Q004100083Q000300305F00080001002000122Q000900043Q00203A000A0005001E2Q006200090002000200102200080003000900305F0008000500062Q006C00060008000100203A00060005002100061F00060060000100010004113Q0060000100203A0006000500220006420006007800013Q0004113Q0078000100122Q0006001D3Q00203A00060006001F2Q0059000700034Q004100083Q000300305F00080001002300122Q000900243Q00203A00090009002500123E000A00263Q00122Q000B00043Q00203A000C0005002100061F000C006D000100010004113Q006D000100123E000C00274Q0062000B0002000200122Q000C00043Q00203A000D0005002200061F000D0073000100010004113Q0073000100123E000D00274Q000F000C000D4Q005D00093Q000200102200080003000900305F0008000500062Q006C00060008000100203A0006000500280006420006008800013Q0004113Q0088000100122Q0006001D3Q00203A00060006001F2Q0059000700034Q004100083Q000300305F00080001002900122Q000900043Q00203A000A000500282Q006200090002000200123E000A002A4Q000200090009000A00102200080003000900305F0008000500062Q006C00060008000100122Q000400194Q004F000500024Q006200040002000200265C000400A20001001A0004113Q00A2000100122Q0004001B4Q004F000500024Q0054000400020005000642000400A200013Q0004113Q00A2000100122Q0006001C4Q0059000700054Q006200060002000200265C000600A20001001D0004113Q00A2000100122Q0006002B4Q0059000700054Q00540006000200080004113Q00A0000100122Q000B001D3Q00203A000B000B001F2Q0059000C00034Q0059000D000A4Q006C000B000D00010006600006009B000100020004113Q009B000100122Q0004001C4Q0059000500024Q006200040002000200265C000400BF0001001D0004113Q00BF000100122Q0004002C4Q0059000500024Q00540004000200060004113Q00BD000100122Q0009001D3Q00203A00090009001F2Q0059000A00034Q0041000B3Q000300122Q000C00044Q0059000D00074Q0062000C00020002001022000B0001000C00122Q000C00044Q0059000D00084Q0062000C0002000200201E000C000C000800123E000E00093Q00123E000F002D4Q0068000C000F0002001022000B0003000C00305F000B000500062Q006C0009000B0001000660000400AB000100020004113Q00AB00012Q000C000300024Q00013Q00017Q001F3Q0003043Q007479706503063Q00737472696E6703043Q0066696E6403013Q000A034Q0003143Q00526561736F6E206E6F742073706563696669656403063Q00736F7572636503063Q00726561736F6E03023Q00617403023Q006F7303043Q0074696D6503063Q0075736572496403063Q0055736572496403083Q00757365724E616D6503043Q004E616D6503053Q006A6F62496403043Q0067616D6503053Q004A6F62496403073Q00706C616365496403073Q00506C616365496403043Q007761726E031D3Q005B4D415849204855425D204B69636B202F20646973636F2Q6E6563743A03013Q002D03083Q00746F737472696E672Q033Q00737562026Q00F03F026Q006E4003053Q007072696E7403193Q005B4D415849204855425D204B69636B206C6F2Q676564202D3E03043Q007461736B03053Q00737061776E03684Q004F00035Q0006420003000400013Q0004113Q000400012Q00013Q00013Q00122Q000300014Q0059000400014Q006200030002000200265C00030013000100020004113Q0013000100201E00030001000300123E000500044Q00680003000500020006420003001300013Q0004113Q001300012Q004F000300014Q0059000400014Q006200030002000200060700010013000100030004113Q001300012Q004F000300024Q005900046Q0059000500014Q00680003000500020006420003001A00013Q0004113Q001A00012Q00013Q00013Q0006420001001E00013Q0004113Q001E000100265C0001001F000100050004113Q001F000100123E000100064Q0004000300014Q006E00036Q006E000100034Q006E3Q00044Q004100033Q0007001022000300073Q00102200030008000100122Q0004000A3Q00203A00040004000B2Q00180004000100020010220003000900042Q004F000400053Q0006420004003100013Q0004113Q003100012Q004F000400053Q00203A00040004000D00061F00040032000100010004113Q003200012Q0014000400043Q0010220003000C00042Q004F000400053Q0006420004003A00013Q0004113Q003A00012Q004F000400053Q00203A00040004000F00061F0004003B000100010004113Q003B00012Q0014000400043Q0010220003000E000400122Q000400113Q00203A00040004001200102200030010000400122Q000400113Q00203A0004000400140010220003001300042Q004F000400064Q0059000500034Q005600040002000100122Q000400153Q00123E000500164Q005900065Q00123E000700173Q00122Q000800184Q0059000900014Q006200080002000200201E00080008001900123E000A001A3Q00123E000B001B4Q00690008000B4Q000600043Q000100122Q0004001C3Q00123E0005001D4Q004F000600074Q006C0004000600012Q004F000400084Q00180004000100020006420004005B00013Q0004113Q005B000100265C0004005C000100050004113Q005C00012Q00013Q00013Q00122Q0005001E3Q00203A00050005001F00062B00063Q000100072Q00473Q00094Q00213Q00044Q00473Q000A4Q00473Q000B4Q00218Q00213Q00014Q00213Q00024Q00560005000200012Q00013Q00013Q00013Q00013Q0003053Q007063612Q6C000B3Q00124Q00013Q00062B00013Q000100072Q00478Q00473Q00014Q00473Q00024Q00473Q00034Q00473Q00044Q00473Q00054Q00473Q00064Q00563Q000200012Q00013Q00013Q00013Q00153Q002Q033Q0055726C03063Q004D6574686F6403043Q00504F535403073Q0048656164657273030C3Q00436F6E74656E742D5479706503103Q00612Q706C69636174696F6E2F6A736F6E03043Q00426F6479030A3Q004A534F4E456E636F646503063Q00656D6265647303053Q007469746C6503113Q004B69636B202F20646973636F2Q6E65637403053Q00636F6C6F72023Q008087E96C4103063Q006669656C647303063Q00662Q6F74657203043Q007465787403143Q004D4158492048554220C2B7206B69636B206C6F6703093Q0074696D657374616D7003083Q004461746554696D652Q033Q006E6F7703093Q00546F49736F4461746500244Q004F8Q004100013Q00042Q004F000200013Q00102200010001000200305F0001000200032Q004100023Q000100305F0002000500060010220001000400022Q004F000200023Q00201E0002000200082Q004100043Q00012Q0041000500014Q004100063Q000500305F0006000A000B00305F0006000C000D2Q004F000700034Q004F000800044Q004F000900054Q004F000A00064Q00680007000A00020010220006000E00072Q004100073Q000100305F0007001000110010220006000F000700122Q000700133Q00203A0007000700142Q001800070001000200201E0007000700152Q00620007000200020010220006001200072Q00080005000100010010220004000900052Q00680002000400020010220001000700022Q00563Q000200012Q00013Q00017Q00033Q0003043Q007479706503063Q00737472696E67034Q0002114Q004F00026Q005900036Q0059000400014Q00680002000400020006420002000700013Q0004113Q000700012Q00013Q00013Q00122Q000200014Q0059000300014Q006200020002000200265C00020010000100020004113Q0010000100263300010010000100030004113Q001000012Q006E000100014Q006E3Q00024Q00013Q00017Q00053Q00026Q001840028Q0003053Q007461626C6503063Q00636F6E63617403013Q000A02143Q00061F00010003000100010004113Q0003000100123E000100014Q004100025Q00062B00033Q000100042Q00213Q00014Q00478Q00213Q00024Q00213Q00034Q0059000400034Q005900055Q00123E000600024Q006C00040006000100122Q000400033Q00203A0004000400042Q0059000500023Q00123E000600054Q0029000400064Q005A00046Q00013Q00013Q00013Q000B3Q002Q033Q0049734103093Q00546578744C6162656C030A3Q005465787442752Q746F6E03073Q0054657874426F7803043Q0054657874034Q0003053Q007461626C6503063Q00696E7365727403063Q00697061697273030B3Q004765744368696C6472656E026Q00F03F022E4Q004F00025Q00067100020004000100010004113Q000400012Q00013Q00013Q00201E00023Q000100123E000400024Q006800020004000200061F00020013000100010004113Q0013000100201E00023Q000100123E000400034Q006800020004000200061F00020013000100010004113Q0013000100201E00023Q000100123E000400044Q00680002000400020006420002002200013Q0004113Q0022000100203A00023Q00050006420002002200013Q0004113Q0022000100263300020022000100060004113Q002200012Q004F000300014Q0059000400024Q006200030002000200061F00030022000100010004113Q0022000100122Q000300073Q00203A0003000300082Q004F000400024Q0059000500024Q006C00030005000100122Q000200093Q00201E00033Q000A2Q000F000300044Q003F00023Q00040004113Q002B00012Q004F000700034Q0059000800063Q00201C00090001000B2Q006C00070009000100066000020027000100020004113Q002700012Q00013Q00017Q00013Q0003063Q00506172656E74010F4Q005900015Q0006420001000D00013Q0004113Q000D00012Q004F00025Q0006500001000D000100020004113Q000D000100203A0002000100012Q004F00035Q0006030002000B000100030004113Q000B00012Q000C000100023Q00203A0001000100010004113Q000100012Q000C3Q00024Q00013Q00017Q000E3Q0003053Q007063612Q6C03073Q004D652Q73616765034Q00030A3Q004775695365727669636503043Q005479706503123Q00436F2Q6E656374696F6E20652Q726F723A2003083Q00746F737472696E6703063Q00697061697273030B3Q004765744368696C6472656E03043Q004E616D6503083Q00436F72654775693A030E3Q0047657444657363656E64616E74732Q033Q0049734103093Q005363722Q656E477569008D3Q00124Q00013Q00062B00013Q000100012Q00478Q00543Q000200010006423Q003B00013Q0004113Q003B00010006420001003B00013Q0004113Q003B000100203A0002000100020006420002001B00013Q0004113Q001B000100203A0002000100020026330002001B000100030004113Q001B00012Q004F000200013Q00203A0003000100022Q006200020002000200061F0002001B000100010004113Q001B000100123E000200044Q004F000300023Q00203A0004000100022Q006200030002000200061F0003001A000100010004113Q001A000100203A0003000100022Q0023000200034Q004F000200033Q00203A0003000100052Q00620002000200020006420002003B00013Q0004113Q003B000100203A0002000100020006420002002900013Q0004113Q0029000100203A00020001000200263300020029000100030004113Q0029000100203A00020001000200061F0002002E000100010004113Q002E000100123E000200063Q00122Q000300073Q00203A0004000100052Q00620003000200022Q00020002000200032Q004F000300014Q0059000400024Q006200030002000200061F0003003B000100010004113Q003B000100123E000300044Q004F000400024Q0059000500024Q006200040002000200061F0004003A000100010004113Q003A00012Q0059000400024Q0023000300033Q00122Q000200084Q004F000300043Q00201E0003000300092Q000F000300044Q003F00023Q00040004113Q005E00012Q004F000700053Q00203A00080006000A2Q006200070002000200061F0007005E000100010004113Q005E00012Q004F000700063Q00203A00080006000A2Q00620007000200020006420007005E00013Q0004113Q005E00012Q004F000700074Q0059000800064Q00620007000200022Q004F000800024Q0059000900074Q00620008000200020026330008005E000100030004113Q005E00012Q004F000900084Q0059000A00083Q00203A000B0006000A2Q00680009000B00020006420009005E00013Q0004113Q005E000100123E0009000B3Q00203A000A0006000A2Q000200090009000A2Q0059000A00084Q0023000900033Q00066000020041000100020004113Q0041000100122Q000200084Q004F000300043Q00201E00030003000C2Q000F000300044Q003F00023Q00040004113Q0088000100201E00070006000D00123E0009000E4Q00680007000900020006420007008800013Q0004113Q008800012Q004F000700053Q00203A00080006000A2Q006200070002000200061F00070088000100010004113Q008800012Q004F000700063Q00203A00080006000A2Q00620007000200020006420007008800013Q0004113Q008800012Q004F000700074Q0059000800064Q00620007000200022Q004F000800024Q0059000900074Q006200080002000200263300080088000100030004113Q008800012Q004F000900084Q0059000A00083Q00203A000B0006000A2Q00680009000B00020006420009008800013Q0004113Q0088000100123E0009000B3Q00203A000A0006000A2Q000200090009000A2Q0059000A00084Q0023000900033Q00066000020066000100020004113Q006600012Q0014000200034Q0023000200034Q00013Q00013Q00013Q00013Q00030F3Q00476574452Q726F724D652Q7361676500054Q004F7Q00201E5Q00012Q00293Q00014Q005A8Q00013Q00017Q00043Q0003063Q00506172656E7403043Q004E616D65034Q0003083Q00436F72654775693A014A3Q0006423Q000500013Q0004113Q0005000100203A00013Q000100061F00010006000100010004113Q000600012Q00013Q00014Q004F00016Q005900026Q00620001000200020006420001000C00013Q0004113Q000C00012Q00013Q00014Q004F000100014Q005900026Q00620001000200020006420001001400013Q0004113Q0014000100203A00020001000200061F00020015000100010004113Q0015000100203A00023Q00022Q004F000300024Q0059000400024Q00620003000200020006420003002000013Q0004113Q002000012Q004F00035Q0006070004001E000100010004113Q001E00012Q005900046Q00560003000200012Q00013Q00014Q004F000300034Q0059000400024Q006200030002000200061F0003002B000100010004113Q002B00012Q004F000300033Q00203A00043Q00022Q006200030002000200061F0003002B000100010004113Q002B00012Q00013Q00014Q004F000300043Q0006070004002F000100010004113Q002F00012Q005900046Q00620003000200022Q004F000400054Q0059000500034Q006200040002000200265C00040036000100030004113Q003600012Q00013Q00014Q004F000500064Q0059000600044Q0059000700024Q006800050007000200061F0005003D000100010004113Q003D00012Q00013Q00014Q004F000500073Q00123E000600044Q0059000700024Q00020006000600072Q0059000700044Q006C0005000700012Q004F000500083Q00123E000600044Q0059000700024Q00020006000600072Q0059000700044Q006C0005000700012Q00013Q00017Q000A3Q0003063Q00506172656E7403063Q00737472696E6703053Q006C6F77657203043Q004E616D6503043Q0066696E64030B3Q00652Q726F7270726F6D7074026Q00F03F030C3Q00652Q726F726D652Q7361676503043Q007461736B03053Q006465666572012B3Q0006423Q000500013Q0004113Q0005000100203A00013Q000100061F00010006000100010004113Q000600012Q00013Q00014Q004F00016Q005900026Q00620001000200020006420001000C00013Q0004113Q000C00012Q00013Q00013Q00122Q000100023Q00203A00010001000300203A00023Q00042Q00620001000200022Q004F000200013Q00203A00033Q00042Q006200020002000200061F00020021000100010004113Q0021000100201E00020001000500123E000400063Q00123E000500074Q0004000600014Q006800020006000200061F00020021000100010004113Q0021000100201E00020001000500123E000400083Q00123E000500074Q0004000600014Q006800020006000200061F00020024000100010004113Q002400012Q00013Q00013Q00122Q000300093Q00203A00030003000A00062B00043Q000100022Q00473Q00024Q00218Q00560003000200012Q00013Q00013Q00013Q00033Q0003043Q007461736B03043Q0077616974026Q33C33F00083Q00124Q00013Q00203A5Q000200123E000100034Q00563Q000200012Q004F8Q004F000100014Q00563Q000200012Q00013Q00017Q00083Q0003063Q00747970656F66030E3Q00682Q6F6B6D6574616D6574686F6403083Q0066756E6374696F6E03113Q006765746E616D6563612Q6C6D6574686F64030B3Q006E65772Q636C6F73757265030B3Q004C6F63616C506C6179657203043Q0067616D65030A3Q002Q5F6E616D6563612Q6C00243Q00124Q00013Q00122Q000100024Q00623Q0002000200265C3Q000A000100030004113Q000A000100124Q00013Q00122Q000100044Q00623Q000200020026333Q000B000100030004113Q000B00012Q00013Q00013Q00124Q00053Q00061F3Q000F000100010004113Q000F000100021B8Q004F00015Q00061F00010014000100010004113Q001400012Q004F000100013Q00203A00010001000600061F00010017000100010004113Q001700012Q00013Q00014Q0014000200023Q00122Q000300023Q00122Q000400073Q00123E000500084Q005900065Q00062B00070001000100032Q00213Q00014Q00473Q00024Q00213Q00024Q000F000600074Q005D00033Q00022Q0059000200034Q00013Q00013Q00027Q0001024Q000C3Q00024Q00013Q00017Q00073Q0003113Q006765746E616D6563612Q6C6D6574686F6403043Q004B69636B00034Q0003163Q004B69636B28292077697468206E6F206D652Q73616765030B3Q00506C617965723A4B69636B03083Q00746F737472696E6701193Q00122Q000200014Q00180002000100022Q004F00035Q0006033Q0013000100030004113Q0013000100265C00020013000100020004113Q001300012Q0065000300043Q0026330003000C000100030004113Q000C000100265C0003000D000100040004113Q000D000100123E000300054Q004F000400013Q00123E000500063Q00122Q000600074Q0059000700034Q000F000600074Q000600043Q00012Q004F000300024Q005900046Q001900056Q006F00036Q005A00036Q00013Q00017Q00023Q0003133Q00452Q726F724D652Q736167654368616E67656403073Q00436F2Q6E656374000D4Q004F8Q004F000100013Q00203A00010001000100201E00010001000200062B00033Q000100052Q00473Q00014Q00473Q00024Q00473Q00034Q00473Q00044Q00473Q00054Q0069000100034Q00065Q00012Q00013Q00013Q00013Q00073Q0003053Q007063612Q6C03073Q004D652Q7361676503043Q005479706503083Q00746F737472696E67034Q0003123Q00436F2Q6E656374696F6E20652Q726F723A20030A3Q004775695365727669636500473Q00124Q00013Q00062B00013Q000100012Q00478Q00543Q000200010006423Q000800013Q0004113Q0008000100061F00010009000100010004113Q000900012Q00013Q00013Q00203A00020001000200203A0003000100030006420003001400013Q0004113Q001400012Q004100033Q000100122Q000400043Q00203A0005000100032Q006200040002000200102200030003000400061F00030015000100010004113Q001500012Q0014000300033Q0006420002001900013Q0004113Q0019000100265C00020023000100050004113Q002300012Q004F000400013Q00203A0005000100032Q00620004000200020006420004002300013Q0004113Q0023000100123E000400063Q00122Q000500043Q00203A0006000100032Q00620005000200022Q00020002000400050006420002003800013Q0004113Q0038000100263300020038000100050004113Q003800012Q004F000400024Q0059000500024Q006200040002000200061F0004002D000100010004113Q002D00012Q0059000400024Q004F000500034Q0059000600044Q00620005000200020006420005004600013Q0004113Q004600012Q004F000500043Q00123E000600074Q0059000700044Q0059000800034Q006C0005000800010004113Q004600012Q004F000400013Q00203A0005000100032Q00620004000200020006420004004600013Q0004113Q004600012Q004F000400043Q00123E000500073Q00123E000600063Q00122Q000700043Q00203A0008000100032Q00620007000200022Q00020006000600072Q0059000700034Q006C0004000700012Q00013Q00013Q00013Q00013Q00030F3Q00476574452Q726F724D652Q7361676500054Q004F7Q00201E5Q00012Q00293Q00014Q005A8Q00013Q00017Q00023Q0003193Q004C6F63616C506C6179657254656C65706F72744661696C656403073Q00436F2Q6E656374000B4Q004F8Q004F000100013Q00203A00010001000100201E00010001000200062B00033Q000100032Q00473Q00024Q00473Q00034Q00473Q00044Q0069000100034Q00065Q00012Q00013Q00013Q00013Q00043Q0003083Q00746F737472696E67030F3Q0054656C65706F7274206661696C6564030E3Q0054656C65706F72744661696C656403063Q00526573756C74031B3Q00122Q000300013Q00060700040006000100020004113Q0006000100060700040006000100010004113Q0006000100123E000400024Q00620003000200022Q004F00046Q0059000500034Q006200040002000200061F00040011000100010004113Q001100012Q004F000400014Q0059000500034Q00620004000200020006420004001A00013Q0004113Q001A00012Q004F000400023Q00123E000500034Q0059000600034Q004100073Q000100122Q000800014Q0059000900014Q00620008000200020010220007000400082Q006C0004000700012Q00013Q00017Q00023Q00030F3Q0044657363656E64616E74412Q64656403073Q00436F2Q6E65637400113Q00062B5Q000100022Q00478Q00473Q00014Q005900016Q004F000200024Q00560001000200012Q004F000100034Q004F000200023Q00203A00020002000100201E00020002000200062B00040001000100032Q00478Q00473Q00044Q00473Q00014Q0069000200044Q000600013Q00012Q00013Q00013Q00023Q00023Q0003063Q00697061697273030E3Q0047657444657363656E64616E7473011B3Q00061F3Q0003000100010004113Q000300012Q00013Q00013Q00122Q000100013Q00201E00023Q00022Q000F000200034Q003F00013Q00030004113Q000B00012Q004F00066Q0059000700054Q005600060002000100066000010008000100020004113Q000800012Q004F000100014Q005900026Q005600010002000100122Q000100013Q00201E00023Q00022Q000F000200034Q003F00013Q00030004113Q001800012Q004F000600014Q0059000700054Q005600060002000100066000010015000100020004113Q001500012Q00013Q00017Q00013Q0003043Q004E616D6501104Q004F00016Q005900026Q00620001000200020006420001000600013Q0004113Q000600012Q00013Q00014Q004F000100013Q00203A00023Q00012Q006200010002000200061F0001000C000100010004113Q000C00012Q00013Q00014Q004F000100024Q005900026Q00560001000200012Q00013Q00017Q00053Q0003043Q0067616D65030A3Q0047657453657276696365030A3Q004C6F6753657276696365030A3Q004D652Q736167654F757403073Q00436F2Q6E65637400153Q00124Q00013Q00201E5Q000200123E000200034Q00683Q000200020006423Q000900013Q0004113Q0009000100203A00013Q000400061F0001000A000100010004113Q000A00012Q00013Q00014Q004F00015Q00203A00023Q000400201E00020002000500062B00043Q000100042Q00473Q00014Q00473Q00024Q00473Q00034Q00473Q00044Q0069000200044Q000600013Q00012Q00013Q00013Q00013Q00053Q0003043Q00456E756D030B3Q004D652Q7361676554797065030C3Q004D652Q73616765452Q726F72030E3Q004D652Q736167655761726E696E67030A3Q004C6F6753657276696365021E3Q00122Q000200013Q00203A00020002000200203A0002000200030006500001000B000100020004113Q000B000100122Q000200013Q00203A00020002000200203A0002000200040006500001000B000100020004113Q000B00012Q00013Q00014Q004F00026Q005900036Q006200020002000200061F00020015000100010004113Q001500012Q004F000200014Q005900036Q00620002000200020006420002001D00013Q0004113Q001D00012Q004F000200023Q00123E000300054Q005900046Q006C0002000400012Q004F000200033Q00123E000300054Q005900046Q006C0002000400012Q00013Q00017Q00033Q00030B3Q004C6F63616C506C61796572030E3Q00506C6179657252656D6F76696E6703073Q00436F2Q6E65637400174Q004F7Q00061F3Q0005000100010004113Q000500012Q004F3Q00013Q00203A5Q000100061F3Q0008000100010004113Q000800012Q00013Q00014Q004F000100024Q004F000200013Q00203A00020002000200201E00020002000300062B00043Q000100072Q00218Q00473Q00034Q00473Q00044Q00473Q00054Q00473Q00064Q00473Q00074Q00473Q00084Q0069000200044Q000600013Q00012Q00013Q00013Q00013Q00013Q00030E3Q00506C6179657252656D6F76696E67011F4Q004F00015Q0006503Q0004000100010004113Q000400012Q00013Q00014Q004F000100013Q0006420001000800013Q0004113Q000800012Q00013Q00014Q004F000100024Q004800010001000200061F0002000D000100010004113Q000D00012Q004F000200033Q00061F00010013000100010004113Q001300012Q004F000300043Q00060700010013000100030004113Q0013000100123E000100013Q0006420002001E00013Q0004113Q001E00012Q004F000300054Q0059000400024Q00620003000200020006420003001E00013Q0004113Q001E00012Q004F000300064Q0059000400014Q0059000500024Q006C0003000500012Q00013Q00017Q00033Q00028Q0003093Q0048656172746265617403073Q00436F2Q6E656374000F3Q00123E3Q00014Q004F00016Q004F000200013Q00203A00020002000200201E00020002000300062B00043Q000100062Q00218Q00473Q00024Q00473Q00034Q00473Q00044Q00473Q00054Q00473Q00064Q0069000200044Q000600013Q00012Q00013Q00013Q00013Q00023Q00026Q00F83F028Q00011F4Q004F00016Q0038000100014Q006E00016Q004F00015Q00262000010007000100010004113Q000700012Q00013Q00013Q00123E000100024Q006E00016Q004F000100013Q0006420001000D00013Q0004113Q000D00012Q00013Q00014Q004F000100024Q00480001000100020006420002001E00013Q0004113Q001E00012Q004F000300034Q0059000400024Q00620003000200020006420003001E00013Q0004113Q001E00012Q004F000300044Q0059000400014Q0059000500024Q006C0003000500012Q004F000300054Q0059000400014Q0059000500024Q006C0003000500012Q00013Q00017Q00", GetFEnv(), ...);