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
										local A = Inst[2];
										Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
									else
										VIP = Inst[3];
									end
								elseif (Enum == 2) then
									if (Stk[Inst[2]] == Inst[4]) then
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
							elseif (Enum <= 5) then
								if (Enum == 4) then
									local A = Inst[2];
									local T = Stk[A];
									for Idx = A + 1, Inst[3] do
										Insert(T, Stk[Idx]);
									end
								else
									Stk[Inst[2]] = Stk[Inst[3]];
								end
							elseif (Enum <= 6) then
								Stk[Inst[2]] = {};
							elseif (Enum == 7) then
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							else
								Stk[Inst[2]][Inst[3]] = Inst[4];
							end
						elseif (Enum <= 13) then
							if (Enum <= 10) then
								if (Enum > 9) then
									Stk[Inst[2]] = Inst[3] ~= 0;
									VIP = VIP + 1;
								else
									local A = Inst[2];
									do
										return Stk[A], Stk[A + 1];
									end
								end
							elseif (Enum <= 11) then
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
							elseif (Enum == 12) then
								if (Stk[Inst[2]] == Inst[4]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						elseif (Enum <= 15) then
							if (Enum > 14) then
								local A = Inst[2];
								local Results = {Stk[A](Stk[A + 1])};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							end
						elseif (Enum <= 16) then
							local B = Inst[3];
							local K = Stk[B];
							for Idx = B + 1, Inst[4] do
								K = K .. Stk[Idx];
							end
							Stk[Inst[2]] = K;
						elseif (Enum == 17) then
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
								if (Mvm[1] == 24) then
									Indexes[Idx - 1] = {Stk,Mvm[3]};
								else
									Indexes[Idx - 1] = {Upvalues,Mvm[3]};
								end
								Lupvals[#Lupvals + 1] = Indexes;
							end
							Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
						else
							local A = Inst[2];
							do
								return Unpack(Stk, A, Top);
							end
						end
					elseif (Enum <= 27) then
						if (Enum <= 22) then
							if (Enum <= 20) then
								if (Enum == 19) then
									local A = Inst[2];
									Stk[A](Unpack(Stk, A + 1, Top));
								else
									Stk[Inst[2]] = Inst[3];
								end
							elseif (Enum > 21) then
								local A = Inst[2];
								do
									return Unpack(Stk, A, A + Inst[3]);
								end
							else
								do
									return Stk[Inst[2]];
								end
							end
						elseif (Enum <= 24) then
							if (Enum > 23) then
								Stk[Inst[2]] = Stk[Inst[3]];
							else
								Stk[Inst[2]]();
							end
						elseif (Enum <= 25) then
							local B = Inst[3];
							local K = Stk[B];
							for Idx = B + 1, Inst[4] do
								K = K .. Stk[Idx];
							end
							Stk[Inst[2]] = K;
						elseif (Enum > 26) then
							Stk[Inst[2]] = Upvalues[Inst[3]];
						else
							local A = Inst[2];
							Stk[A] = Stk[A](Stk[A + 1]);
						end
					elseif (Enum <= 32) then
						if (Enum <= 29) then
							if (Enum > 28) then
								local A = Inst[2];
								Stk[A] = Stk[A]();
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
						elseif (Enum <= 30) then
							Stk[Inst[2]] = Env[Inst[3]];
						elseif (Enum > 31) then
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
							VIP = Inst[3];
						end
					elseif (Enum <= 34) then
						if (Enum > 33) then
							local A = Inst[2];
							do
								return Unpack(Stk, A, Top);
							end
						else
							local A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
						end
					elseif (Enum <= 35) then
						if not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum == 36) then
						local A = Inst[2];
						Stk[A] = Stk[A]();
					else
						Stk[Inst[2]] = Inst[3] ~= 0;
						VIP = VIP + 1;
					end
				elseif (Enum <= 56) then
					if (Enum <= 46) then
						if (Enum <= 41) then
							if (Enum <= 39) then
								if (Enum > 38) then
									Stk[Inst[2]] = Inst[3] ~= 0;
								else
									local A = Inst[2];
									local B = Stk[Inst[3]];
									Stk[A + 1] = B;
									Stk[A] = B[Inst[4]];
								end
							elseif (Enum > 40) then
								Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
							else
								Stk[Inst[2]] = Inst[3];
							end
						elseif (Enum <= 43) then
							if (Enum > 42) then
								Stk[Inst[2]] = {};
							elseif (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum <= 44) then
							for Idx = Inst[2], Inst[3] do
								Stk[Idx] = nil;
							end
						elseif (Enum > 45) then
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
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
					elseif (Enum <= 51) then
						if (Enum <= 48) then
							if (Enum > 47) then
								Stk[Inst[2]][Inst[3]] = Inst[4];
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
									if (Mvm[1] == 24) then
										Indexes[Idx - 1] = {Stk,Mvm[3]};
									else
										Indexes[Idx - 1] = {Upvalues,Mvm[3]};
									end
									Lupvals[#Lupvals + 1] = Indexes;
								end
								Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
							end
						elseif (Enum <= 49) then
							Stk[Inst[2]] = Inst[3] ~= 0;
						elseif (Enum > 50) then
							local A = Inst[2];
							local Results = {Stk[A](Unpack(Stk, A + 1, Inst[3]))};
							local Edx = 0;
							for Idx = A, Inst[4] do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						else
							local A = Inst[2];
							Stk[A](Stk[A + 1]);
						end
					elseif (Enum <= 53) then
						if (Enum > 52) then
							do
								return Stk[Inst[2]];
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
					elseif (Enum <= 54) then
						if Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum == 55) then
						if not Stk[Inst[2]] then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
					end
				elseif (Enum <= 65) then
					if (Enum <= 60) then
						if (Enum <= 58) then
							if (Enum == 57) then
								Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
							elseif Stk[Inst[2]] then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 59) then
							local A = Inst[2];
							do
								return Stk[A], Stk[A + 1];
							end
						else
							local A = Inst[2];
							do
								return Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						end
					elseif (Enum <= 62) then
						if (Enum == 61) then
							local A = Inst[2];
							local T = Stk[A];
							local B = Inst[3];
							for Idx = 1, B do
								T[Idx] = Stk[A + Idx];
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
					elseif (Enum <= 63) then
						local A = Inst[2];
						local B = Stk[Inst[3]];
						Stk[A + 1] = B;
						Stk[A] = B[Inst[4]];
					elseif (Enum > 64) then
						for Idx = Inst[2], Inst[3] do
							Stk[Idx] = nil;
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
				elseif (Enum <= 70) then
					if (Enum <= 67) then
						if (Enum > 66) then
							Stk[Inst[2]]();
						else
							local A = Inst[2];
							Stk[A](Unpack(Stk, A + 1, Top));
						end
					elseif (Enum <= 68) then
						local A = Inst[2];
						local T = Stk[A];
						local B = Inst[3];
						for Idx = 1, B do
							T[Idx] = Stk[A + Idx];
						end
					elseif (Enum == 69) then
						do
							return;
						end
					else
						Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
					end
				elseif (Enum <= 72) then
					if (Enum == 71) then
						Stk[Inst[2]] = Upvalues[Inst[3]];
					else
						local A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
					end
				elseif (Enum <= 73) then
					do
						return;
					end
				elseif (Enum == 74) then
					local A = Inst[2];
					Stk[A](Stk[A + 1]);
				else
					Stk[Inst[2]] = Env[Inst[3]];
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!2E3Q002Q033Q00322E36033C3Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F6B6F744D613073316E2F6D6178692D6875622F6D61737465722F03363Q00682Q7470733A2Q2F63646E2E6A7364656C6976722E6E65742F67682F6B6F744D613073316E2F6D6178692D687562406D61737465722F030C3Q006C61756E636865722E6C756103113Q006D6178692D6875622D617574682E6C756103103Q006D6178692D6875622D6B65792E6C756103113Q006D6178692D6875622D636F72652E6C7561030F3Q006D6178692D6875622D75692E6C756103133Q006D6178692D6875622D6C6F63616C652E6C756103153Q006D6178692D6875622D74656C656772616D2E6C756103103Q006D6178692D6875622D6573702E6C756103163Q006D6178692D6875622D6368616E67656C6F672E6C756103113Q006D6178692D6875622D6B69636B2E6C756103063Q00747970656F6603043Q0067616D6503073Q00482Q747047657403083Q0066756E6374696F6E03053Q00652Q726F7203283Q005B4D415849204855425D204578656375746F72206D7573742073752Q706F727420482Q747047657403093Q00777269746566696C6503083Q007265616466696C6503063Q00697366696C65033A3Q005B4D415849204855425D204578656375746F72206D7573742073752Q706F727420777269746566696C652F7265616466696C652F697366696C65030A3Q0047657453657276696365030B3Q00482Q74705365727669636503073Q0067657467656E7603023Q005F4703123Q004D6178694875624F2Q66696369616C526177026Q00F03F03103Q004D6178694875624C6F6164657255726C030A3Q006C6F616465722E6C7561030F3Q004D6178694875625265706F4F6E6C792Q01030E3Q004D617869487562536B69704B6579010003143Q004D6178694875624C6F6164657256657273696F6E030A3Q006D616B65666F6C64657203053Q007063612Q6C03083Q006D6178692D68756203063Q0069706169727303093Q006D6178692D6875622F03153Q006D6178692D6875622F6C61756E636865722E6C7561030A3Q006C6F6164737472696E67030D3Q00406C61756E636865722E6C756103153Q005B4D415849204855425D206C61756E636865723A2003083Q00746F737472696E6700793Q0012283Q00014Q002B000100023Q001228000200023Q001228000300034Q00440001000200012Q002B0002000A3Q001228000300043Q001228000400053Q001228000500063Q001228000600073Q001228000700083Q001228000800093Q0012280009000A3Q001228000A000B3Q001228000B000C3Q001228000C000D4Q00440002000A000100121E0003000E3Q00121E0004000F3Q00200E0004000400102Q004800030002000200262D0003001A0001001100041F3Q001A000100121E000300123Q001228000400134Q003200030002000100121E0003000E3Q00121E000400144Q004800030002000200260C000300290001001100041F3Q0029000100121E0003000E3Q00121E000400154Q004800030002000200260C000300290001001100041F3Q0029000100121E0003000E3Q00121E000400164Q004800030002000200262D0003002C0001001100041F3Q002C000100121E000300123Q001228000400174Q003200030002000100121E0003000F3Q002026000300030018001228000500194Q002100030005000200023800045Q000238000500013Q000238000600023Q00061100070003000100022Q00183Q00064Q00183Q00033Q00061100080004000100052Q00183Q00044Q00183Q00014Q00183Q00054Q00183Q00074Q00187Q00121E0009000E3Q00121E000A001A4Q004800090002000200260C000900450001001100041F3Q0045000100121E0009001A4Q0024000900010002000637000900460001000100041F3Q0046000100121E0009001B3Q00200E000A0001001D0010290009001C000A00200E000A0001001D001228000B001F4Q0019000A000A000B0010290009001E000A002Q30000900200021002Q30000900220023001029000900243Q00121E000A000E3Q00121E000B00254Q0048000A0002000200260C000A00580001001100041F3Q0058000100121E000A00263Q00121E000B00253Q001228000C00274Q000D000A000C000100121E000A00284Q0005000B00024Q000F000A0002000C00041F3Q0064000100121E000F00143Q001228001000294Q00050011000E4Q00190010001000112Q0005001100084Q00050012000E4Q003E001100124Q0013000F3Q000100061C000A005C0001000200041F3Q005C000100121E000A00153Q001228000B002A4Q0048000A0002000200121E000B002B4Q0005000C000A3Q001228000D002C4Q002E000B000D000C000637000B00760001000100041F3Q0076000100121E000D00123Q001228000E002D3Q00121E000F002E4Q00050010000C4Q0048000F000200022Q0019000E000E000F2Q0032000D000200012Q0005000D000B4Q0017000D000100012Q00493Q00013Q00053Q000A3Q0003063Q00747970656F6603023Q006F7303053Q007461626C6503043Q0074696D65028Q0003043Q006D61746803063Q0072616E646F6D025Q00408F40024Q008087C34003083Q00746F737472696E6700293Q00121E3Q00013Q00121E000100024Q00483Q0002000200260C3Q000E0001000300041F3Q000E000100121E3Q00023Q00200E5Q000400063A3Q000E00013Q00041F3Q000E000100121E3Q00023Q00200E5Q00042Q00243Q000100020006373Q000F0001000100041F3Q000F00010012283Q00053Q00121E000100013Q00121E000200064Q004800010002000200260C0001001F0001000300041F3Q001F000100121E000100063Q00200E00010001000700063A0001001F00013Q00041F3Q001F000100121E000100063Q00200E000100010007001228000200083Q001228000300094Q0021000100030002000637000100200001000100041F3Q00200001001228000100053Q00121E0002000A4Q000500036Q004800020002000200121E0003000A4Q0005000400014Q00480003000200022Q00190002000200032Q0035000200024Q00493Q00017Q000B3Q0003063Q00747970656F6603043Q0067616D6503073Q00482Q747047657403083Q0066756E6374696F6E03053Q007063612Q6C03043Q007479706503063Q00737472696E67034Q0003073Q007265717565737403053Q007461626C6503043Q00426F647901443Q00121E000100013Q00121E000200023Q00200E0002000200032Q004800010002000200260C000100270001000400041F3Q0027000100121E000100053Q00121E000200023Q00200E0002000200032Q000500036Q0031000400014Q002E00010004000200063A0001001600013Q00041F3Q0016000100121E000300064Q0005000400024Q004800030002000200260C000300160001000700041F3Q0016000100262D000200160001000800041F3Q001600012Q0035000200023Q00121E000300053Q00121E000400023Q00200E0004000400032Q000500056Q002E0003000500042Q0005000200044Q0005000100033Q00063A0001002700013Q00041F3Q0027000100121E000300064Q0005000400024Q004800030002000200260C000300270001000700041F3Q0027000100262D000200270001000800041F3Q002700012Q0035000200023Q00121E000100013Q00121E000200094Q004800010002000200260C000100410001000400041F3Q0041000100121E000100053Q00061100023Q000100012Q00188Q000F00010002000200063A0001004100013Q00041F3Q0041000100121E000300064Q0005000400024Q004800030002000200260C000300410001000A00041F3Q0041000100121E000300063Q00200E00040002000B2Q004800030002000200260C000300410001000700041F3Q0041000100200E00030002000B00262D000300410001000800041F3Q0041000100200E00030002000B2Q0035000300024Q0041000100014Q0035000100024Q00493Q00013Q00013Q00043Q0003073Q00726571756573742Q033Q0055726C03063Q004D6574686F642Q033Q0047455400083Q00121E3Q00014Q002B00013Q00022Q001B00025Q001029000100020002002Q300001000300042Q003B3Q00014Q00228Q00493Q00017Q000C3Q0003043Q007479706503063Q00737472696E67034Q002Q033Q00737562026Q00F03F03013Q00EF027Q004003013Q00BB026Q00084003013Q00BF026Q0010402Q033Q00EFBBBF012A3Q00121E000100014Q000500026Q004800010002000200260C000100070001000200041F3Q0007000100260C3Q00080001000300041F3Q000800012Q00353Q00023Q00202600013Q0004001228000300053Q001228000400054Q002100010004000200260C0001001E0001000600041F3Q001E000100202600013Q0004001228000300073Q001228000400074Q002100010004000200260C0001001E0001000800041F3Q001E000100202600013Q0004001228000300093Q001228000400094Q002100010004000200260C0001001E0001000A00041F3Q001E000100202600013Q00040012280003000B4Q003B000100034Q002200015Q00202600013Q0004001228000300053Q001228000400094Q002100010004000200260C000100280001000C00041F3Q0028000100202600013Q00040012280003000B4Q003B000100034Q002200016Q00353Q00024Q00493Q00017Q000A3Q0003043Q007479706503063Q00737472696E67034Q002Q033Q00737562026Q0014C003053Q002E6A736F6E03053Q007063612Q6C030A3Q006C6F6164737472696E6703013Q00400002274Q001B00026Q0005000300014Q00480002000200022Q0005000100023Q00121E000200014Q0005000300014Q004800020002000200260C0002000B0001000200041F3Q000B000100260C0001000D0001000300041F3Q000D00012Q003100026Q0035000200023Q00202600023Q0004001228000400054Q002100020004000200260C0002001A0001000600041F3Q001A000100121E000200073Q00061100033Q000100022Q00473Q00014Q00183Q00014Q00480002000200022Q0005000300024Q0005000400014Q003C000300033Q00121E000200084Q0005000300013Q001228000400094Q000500056Q00190004000400052Q002100020004000200260C000200230001000A00041F3Q002300012Q002500036Q0031000300014Q0005000400014Q003C000300034Q00493Q00013Q00013Q00013Q00030A3Q004A534F4E4465636F646500054Q001B7Q0020265Q00012Q001B000200014Q000D3Q000200012Q00493Q00017Q00063Q0003063Q006970616972732Q033Q003F763D03053Q00652Q726F72031C3Q005B4D415849204855425D20446F776E6C6F6164206661696C65643A20030A3Q0020286C6F61646572207603013Q002901204Q001B00016Q002400010001000200121E000200014Q001B000300014Q000F00020002000400041F3Q001500012Q0005000700064Q000500085Q001228000900024Q0005000A00014Q001900070007000A2Q001B000800024Q0005000900074Q00480008000200022Q001B000900034Q0005000A6Q0005000B00084Q002E0009000B000A00063A0009001500013Q00041F3Q001500012Q0035000A00023Q00061C000200060001000200041F3Q0006000100121E000200033Q001228000300044Q000500045Q001228000500054Q001B000600043Q001228000700064Q00190003000300072Q00320002000200012Q00493Q00017Q00", GetFEnv(), ...);
