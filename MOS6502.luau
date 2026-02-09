--[[

 /$$      /$$  /$$$$$$   /$$$$$$         /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$ 
| $$$    /$$$ /$$__  $$ /$$__  $$       /$$__  $$| $$____/  /$$$_  $$ /$$__  $$
| $$$$  /$$$$| $$  \ $$| $$  \__/      | $$  \__/| $$      | $$$$\ $$|__/  \ $$
| $$ $$/$$ $$| $$  | $$|  $$$$$$       | $$$$$$$ | $$$$$$$ | $$ $$ $$  /$$$$$$/
| $$  $$$| $$| $$  | $$ \____  $$      | $$__  $$|_____  $$| $$\ $$$$ /$$____/ 
| $$\  $ | $$| $$  | $$ /$$  \ $$      | $$  \ $$ /$$  \ $$| $$ \ $$$| $$      
| $$ \/  | $$|  $$$$$$/|  $$$$$$/      |  $$$$$$/|  $$$$$$/|  $$$$$$/| $$$$$$$$
|__/     |__/ \______/  \______/        \______/  \______/  \______/ |________/

Author: @MrRoblick

Repo: https://github.com/MrRoblick/mos6502-luau
Version: 1.0.0
License: MIT

]]

--!strict
--!native
--!optimize 2


--[[ CONSTANTS ]]
local MEMORY_SIZE = 65536 -- 64KB address space

local VECTOR_NMI   = 0xFFFA
local VECTOR_RESET = 0xFFFC
local VECTOR_IRQ   = 0xFFFE

local STACK_BASE = 0x0100
local STACK_TOP  = 0xFD

local FLAG_C = 0
local FLAG_Z = 1
local FLAG_I = 2
local FLAG_D = 3
local FLAG_B = 4
local FLAG_U = 5
local FLAG_V = 6
local FLAG_N = 7

-- [[ BUFFER LAYOUT ]]
local MEMORY_OFFSET = 0
local A_OFFSET      = MEMORY_OFFSET + MEMORY_SIZE
local X_OFFSET      = A_OFFSET + 1
local Y_OFFSET      = X_OFFSET + 1
local SP_OFFSET     = Y_OFFSET + 1
local PC_OFFSET     = SP_OFFSET + 1
local P_OFFSET      = PC_OFFSET + 2
local CYCLES_OFFSET = P_OFFSET + 1
local IRQ_OFFSET    = CYCLES_OFFSET + 4
local NMI_OFFSET    = IRQ_OFFSET + 1
local HALTED_OFFSET = NMI_OFFSET + 1

local BUFFER_SIZE = HALTED_OFFSET + 1


-- [[ REGISTER ACCESS ]]
@native @checked local function WriteA(self: buffer, v: number): ()
	buffer.writeu8(self, A_OFFSET, v)
end
@native @checked local function ReadA(self: buffer): number
	return buffer.readu8(self, A_OFFSET)
end

@native @checked local function WriteX(self: buffer, v: number): ()
	buffer.writeu8(self, X_OFFSET, v)
end
@native @checked local function ReadX(self: buffer): number
	return buffer.readu8(self, X_OFFSET)
end

@native @checked local function WriteY(self: buffer, v: number): ()
	buffer.writeu8(self, Y_OFFSET, v)
end
@native @checked local function ReadY(self: buffer): number
	return buffer.readu8(self, Y_OFFSET)
end

@native @checked local function WriteSP(self: buffer, v: number): ()
	buffer.writeu8(self, SP_OFFSET, v)
end
@native @checked local function ReadSP(self: buffer): number
	return buffer.readu8(self, SP_OFFSET)
end

@native @checked local function WritePC(self: buffer, v: number): ()
	buffer.writeu16(self, PC_OFFSET, v)
end
@native @checked local function ReadPC(self: buffer): number
	return buffer.readu16(self, PC_OFFSET)
end

@native @checked local function WriteP(self: buffer, v: number): ()
	buffer.writeu8(self, P_OFFSET, v)
end
@native @checked local function ReadP(self: buffer): number
	return buffer.readu8(self, P_OFFSET)
end

@native @checked local function WriteCycles(self: buffer, v: number): ()
	buffer.writeu32(self, CYCLES_OFFSET, v)
end
@native @checked local function ReadCycles(self: buffer): number
	return buffer.readu32(self, CYCLES_OFFSET)
end

@native @checked local function WriteIRQ(self: buffer, v: number): ()
	buffer.writeu8(self, IRQ_OFFSET, v)
end
@native @checked local function ReadIRQ(self: buffer): number
	return buffer.readu8(self, IRQ_OFFSET)
end

@native @checked local function WriteNMI(self: buffer, v: number): ()
	buffer.writeu8(self, NMI_OFFSET, v)
end
@native @checked local function ReadNMI(self: buffer): number
	return buffer.readu8(self, NMI_OFFSET)
end

@native @checked local function WriteHalted(self: buffer, v: number): ()
	buffer.writeu8(self, HALTED_OFFSET, v)
end
@native @checked local function ReadHalted(self: buffer): number
	return buffer.readu8(self, HALTED_OFFSET)
end


-- [[ MEMORY ACCESS ]]
@native @checked local function MemRead(self: buffer, addr: number): number
	return buffer.readu8(self, MEMORY_OFFSET + bit32.band(addr, 0xFFFF))
end
@native @checked local function MemWrite(self: buffer, addr: number, v: number): ()
	buffer.writeu8(self, MEMORY_OFFSET + bit32.band(addr, 0xFFFF), bit32.band(v, 0xFF))
end
@native @checked local function MemRead16(self: buffer, addr: number): number
	local lo = buffer.readu8(self, MEMORY_OFFSET + bit32.band(addr, 0xFFFF))
	local hi = buffer.readu8(self, MEMORY_OFFSET + bit32.band(addr + 1, 0xFFFF))
	return bit32.bor(lo, bit32.lshift(hi, 8))
end
@native @checked local function MemRead16Bug(self: buffer, addr: number): number
	local lo = buffer.readu8(self, MEMORY_OFFSET + bit32.band(addr, 0xFFFF))
	local hiAddr = bit32.bor(bit32.band(addr, 0xFF00), bit32.band(addr + 1, 0x00FF))
	local hi = buffer.readu8(self, MEMORY_OFFSET + bit32.band(hiAddr, 0xFFFF))
	return bit32.bor(lo, bit32.lshift(hi, 8))
end


-- [[ STATUS FLAGS ]]
@native @checked local function GetFlag(self: buffer, flag: number): number
	return bit32.band(bit32.rshift(ReadP(self), flag), 1)
end
@native @checked local function SetFlag(self: buffer, flag: number, val: number): ()
	local p = ReadP(self)
	if val ~= 0 then
		p = bit32.bor(p, bit32.lshift(1, flag))
	else
		p = bit32.band(p, bit32.bnot(bit32.lshift(1, flag)))
	end
	WriteP(self, p)
end
@native @checked local function SetZN(self: buffer, val: number): ()
	local v = bit32.band(val, 0xFF)
	SetFlag(self, FLAG_Z, if v == 0 then 1 else 0)
	SetFlag(self, FLAG_N, if bit32.band(v, 0x80) ~= 0 then 1 else 0)
end


-- [[ STACK ]]
@native @checked local function PushByte(self: buffer, val: number): ()
	local sp = ReadSP(self)
	MemWrite(self, STACK_BASE + sp, val)
	WriteSP(self, bit32.band(sp - 1, 0xFF))
end
@native @checked local function PullByte(self: buffer): number
	local sp = bit32.band(ReadSP(self) + 1, 0xFF)
	WriteSP(self, sp)
	return MemRead(self, STACK_BASE + sp)
end
@native @checked local function PushWord(self: buffer, val: number): ()
	PushByte(self, bit32.rshift(bit32.band(val, 0xFF00), 8))
	PushByte(self, bit32.band(val, 0xFF))
end
@native @checked local function PullWord(self: buffer): number
	local lo = PullByte(self)
	local hi = PullByte(self)
	return bit32.bor(lo, bit32.lshift(hi, 8))
end


-- [[ ADDRESSING MODES ]]
@native @checked local function AddrImmediate(self: buffer): number
	local pc = ReadPC(self)
	WritePC(self, pc + 1)
	return pc
end
@native @checked local function AddrZeroPage(self: buffer): number
	local pc = ReadPC(self)
	WritePC(self, pc + 1)
	return MemRead(self, pc)
end
@native @checked local function AddrZeroPageX(self: buffer): number
	local pc = ReadPC(self)
	WritePC(self, pc + 1)
	return bit32.band(MemRead(self, pc) + ReadX(self), 0xFF)
end
@native @checked local function AddrZeroPageY(self: buffer): number
	local pc = ReadPC(self)
	WritePC(self, pc + 1)
	return bit32.band(MemRead(self, pc) + ReadY(self), 0xFF)
end
@native @checked local function AddrAbsolute(self: buffer): number
	local pc = ReadPC(self)
	WritePC(self, pc + 2)
	return MemRead16(self, pc)
end
@native @checked local function AddrAbsoluteX(self: buffer): (number, boolean)
	local pc = ReadPC(self)
	WritePC(self, pc + 2)
	local base = MemRead16(self, pc)
	local addr = bit32.band(base + ReadX(self), 0xFFFF)
	return addr, bit32.band(base, 0xFF00) ~= bit32.band(addr, 0xFF00)
end
@native @checked local function AddrAbsoluteY(self: buffer): (number, boolean)
	local pc = ReadPC(self)
	WritePC(self, pc + 2)
	local base = MemRead16(self, pc)
	local addr = bit32.band(base + ReadY(self), 0xFFFF)
	return addr, bit32.band(base, 0xFF00) ~= bit32.band(addr, 0xFF00)
end
@native @checked local function AddrIndirectX(self: buffer): number
	local pc = ReadPC(self)
	WritePC(self, pc + 1)
	local ptr = bit32.band(MemRead(self, pc) + ReadX(self), 0xFF)
	local lo = MemRead(self, ptr)
	local hi = MemRead(self, bit32.band(ptr + 1, 0xFF))
	return bit32.bor(lo, bit32.lshift(hi, 8))
end
@native @checked local function AddrIndirectY(self: buffer): (number, boolean)
	local pc = ReadPC(self)
	WritePC(self, pc + 1)
	local ptr = MemRead(self, pc)
	local lo = MemRead(self, ptr)
	local hi = MemRead(self, bit32.band(ptr + 1, 0xFF))
	local base = bit32.bor(lo, bit32.lshift(hi, 8))
	local addr = bit32.band(base + ReadY(self), 0xFFFF)
	return addr, bit32.band(base, 0xFF00) ~= bit32.band(addr, 0xFF00)
end
@native @checked local function AddrRelative(self: buffer): number
	local pc = ReadPC(self)
	WritePC(self, pc + 1)
	local offset = MemRead(self, pc)
	if offset >= 128 then
		offset -= 256
	end
	return bit32.band(ReadPC(self) + offset, 0xFFFF)
end


-- [[ ALU ]]
@native @checked local function DoADC(self: buffer, val: number): ()
	local a = ReadA(self)
	local c = GetFlag(self, FLAG_C)
	local sum = a + val + c
	SetFlag(self, FLAG_C, if sum > 0xFF then 1 else 0)
	local result = bit32.band(sum, 0xFF)
	local overflow = bit32.band(bit32.bxor(a, result), bit32.bxor(val, result))
	SetFlag(self, FLAG_V, if bit32.band(overflow, 0x80) ~= 0 then 1 else 0)
	WriteA(self, result)
	SetZN(self, result)
end

@native @checked local function DoSBC(self: buffer, val: number): ()
	DoADC(self, bit32.bxor(val, 0xFF))
end

@native @checked local function DoCMP(self: buffer, regVal: number, memVal: number): ()
	SetFlag(self, FLAG_C, if regVal >= memVal then 1 else 0)
	SetZN(self, regVal - memVal)
end

@native @checked local function DoBranch(self: buffer, addr: number, cycles: number): number
	local pc = ReadPC(self)
	local extra = 1
	if bit32.band(pc, 0xFF00) ~= bit32.band(addr, 0xFF00) then
		extra = 2
	end
	WritePC(self, addr)
	return cycles + extra
end


-- [[ INIT ]]
@native @checked local function Init(self: buffer): ()
	buffer.fill(self, 0, 0, BUFFER_SIZE)
	WriteSP(self, STACK_TOP)
	WriteP(self, bit32.bor(bit32.lshift(1, FLAG_U), bit32.lshift(1, FLAG_I)))
end


-- [[ MODULE ]]
local MOS6502 = {}

local __class = {} do
	@native @checked function __class.LoadProgram(self: MOS6502Instance, program: buffer, Addr: number?): ()
		local loadAddr = Addr or 0x0600
		buffer.copy(self._data, MEMORY_OFFSET + loadAddr, program, 0, buffer.len(program))
	end

	@native @checked function __class.SetResetVector(self: MOS6502Instance, Addr: number): ()
		local data = self._data
		MemWrite(data, VECTOR_RESET, bit32.band(Addr, 0xFF))
		MemWrite(data, VECTOR_RESET + 1, bit32.rshift(Addr, 8))
	end

	@native @checked function __class.SetIRQVector(self: MOS6502Instance, Addr: number): ()
		local data = self._data
		MemWrite(data, VECTOR_IRQ, bit32.band(Addr, 0xFF))
		MemWrite(data, VECTOR_IRQ + 1, bit32.rshift(Addr, 8))
	end

	@native @checked function __class.SetNMIVector(self: MOS6502Instance, Addr: number): ()
		local data = self._data
		MemWrite(data, VECTOR_NMI, bit32.band(Addr, 0xFF))
		MemWrite(data, VECTOR_NMI + 1, bit32.rshift(Addr, 8))
	end

	@native @checked function __class.TriggerIRQ(self: MOS6502Instance): ()
		WriteIRQ(self._data, 1)
	end

	@native @checked function __class.TriggerNMI(self: MOS6502Instance): ()
		WriteNMI(self._data, 1)
	end

	@native @checked function __class.Reset(self: MOS6502Instance): ()
		local data = self._data
		WriteSP(data, STACK_TOP)
		WriteP(data, bit32.bor(bit32.lshift(1, FLAG_U), bit32.lshift(1, FLAG_I)))
		WriteA(data, 0)
		WriteX(data, 0)
		WriteY(data, 0)
		WriteIRQ(data, 0)
		WriteNMI(data, 0)
		WriteHalted(data, 0)
		WritePC(data, MemRead16(data, VECTOR_RESET))
		WriteCycles(data, 7)
	end

	@native @checked function __class.HardReset(self: MOS6502Instance): ()
		Init(self._data)
	end

	@native @checked function __class.ReadMemory(self: MOS6502Instance, Addr: number): number
		return MemRead(self._data, Addr)
	end

	@native @checked function __class.WriteMemory(self: MOS6502Instance, Addr: number, Val: number): ()
		MemWrite(self._data, Addr, Val)
	end

	@native @checked function __class.GetPC(self: MOS6502Instance): number
		return ReadPC(self._data)
	end
	@native @checked function __class.GetA(self: MOS6502Instance): number
		return ReadA(self._data)
	end
	@native @checked function __class.GetX(self: MOS6502Instance): number
		return ReadX(self._data)
	end
	@native @checked function __class.GetY(self: MOS6502Instance): number
		return ReadY(self._data)
	end
	@native @checked function __class.GetSP(self: MOS6502Instance): number
		return ReadSP(self._data)
	end
	@native @checked function __class.GetP(self: MOS6502Instance): number
		return ReadP(self._data)
	end
	@native @checked function __class.GetCycles(self: MOS6502Instance): number
		return ReadCycles(self._data)
	end
	@native @checked function __class.IsHalted(self: MOS6502Instance): boolean
		return ReadHalted(self._data) ~= 0
	end

	@native @checked function __class.Step(self: MOS6502Instance): number
		local data = self._data

		if ReadHalted(data) ~= 0 then
			return 0
		end

		-- NMI
		if ReadNMI(data) ~= 0 then
			WriteNMI(data, 0)
			PushWord(data, ReadPC(data))
			local p = ReadP(data)
			p = bit32.band(p, bit32.bnot(bit32.lshift(1, FLAG_B)))
			p = bit32.bor(p, bit32.lshift(1, FLAG_U))
			PushByte(data, p)
			SetFlag(data, FLAG_I, 1)
			WritePC(data, MemRead16(data, VECTOR_NMI))
			WriteCycles(data, ReadCycles(data) + 7)
			return 7
		end

		-- IRQ
		if ReadIRQ(data) ~= 0 and GetFlag(data, FLAG_I) == 0 then
			WriteIRQ(data, 0)
			PushWord(data, ReadPC(data))
			local p = ReadP(data)
			p = bit32.band(p, bit32.bnot(bit32.lshift(1, FLAG_B)))
			p = bit32.bor(p, bit32.lshift(1, FLAG_U))
			PushByte(data, p)
			SetFlag(data, FLAG_I, 1)
			WritePC(data, MemRead16(data, VECTOR_IRQ))
			WriteCycles(data, ReadCycles(data) + 7)
			return 7
		end

		local pc = ReadPC(data)
		local opcode = MemRead(data, pc)
		WritePC(data, pc + 1)

		local cycles = 0

		if opcode == 0x00 then -- BRK
			WritePC(data, ReadPC(data) + 1)
			PushWord(data, ReadPC(data))
			local p = ReadP(data)
			p = bit32.bor(p, bit32.lshift(1, FLAG_B))
			p = bit32.bor(p, bit32.lshift(1, FLAG_U))
			PushByte(data, p)
			SetFlag(data, FLAG_I, 1)
			WritePC(data, MemRead16(data, VECTOR_IRQ))
			cycles = 7

		elseif opcode == 0x01 then -- ORA (ind,X)
			local addr = AddrIndirectX(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 6

		elseif opcode == 0x05 then -- ORA zpg
			local addr = AddrZeroPage(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 3

		elseif opcode == 0x06 then -- ASL zpg
			local addr = AddrZeroPage(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.lshift(val, 1), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 5

		elseif opcode == 0x08 then -- PHP
			local p = ReadP(data)
			p = bit32.bor(p, bit32.lshift(1, FLAG_B))
			p = bit32.bor(p, bit32.lshift(1, FLAG_U))
			PushByte(data, p)
			cycles = 3

		elseif opcode == 0x09 then -- ORA imm
			local addr = AddrImmediate(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 2

		elseif opcode == 0x0A then -- ASL A
			local a = ReadA(data)
			SetFlag(data, FLAG_C, if bit32.band(a, 0x80) ~= 0 then 1 else 0)
			a = bit32.band(bit32.lshift(a, 1), 0xFF)
			WriteA(data, a)
			SetZN(data, a)
			cycles = 2

		elseif opcode == 0x0D then -- ORA abs
			local addr = AddrAbsolute(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4

		elseif opcode == 0x0E then -- ASL abs
			local addr = AddrAbsolute(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.lshift(val, 1), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x10 then -- BPL
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_N) == 0 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0x11 then -- ORA (ind),Y
			local addr, pg = AddrIndirectY(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 5 + (if pg then 1 else 0)

		elseif opcode == 0x15 then -- ORA zpg,X
			local addr = AddrZeroPageX(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4

		elseif opcode == 0x16 then -- ASL zpg,X
			local addr = AddrZeroPageX(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.lshift(val, 1), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x18 then -- CLC
			SetFlag(data, FLAG_C, 0)
			cycles = 2

		elseif opcode == 0x19 then -- ORA abs,Y
			local addr, pg = AddrAbsoluteY(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x1D then -- ORA abs,X
			local addr, pg = AddrAbsoluteX(data)
			local result = bit32.bor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x1E then -- ASL abs,X
			local addr = AddrAbsoluteX(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.lshift(val, 1), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 7

		elseif opcode == 0x20 then -- JSR abs
			local addr = AddrAbsolute(data)
			PushWord(data, ReadPC(data) - 1)
			WritePC(data, addr)
			cycles = 6

		elseif opcode == 0x21 then -- AND (ind,X)
			local addr = AddrIndirectX(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 6

		elseif opcode == 0x24 then -- BIT zpg
			local addr = AddrZeroPage(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_Z, if bit32.band(ReadA(data), val) == 0 then 1 else 0)
			SetFlag(data, FLAG_V, if bit32.band(val, 0x40) ~= 0 then 1 else 0)
			SetFlag(data, FLAG_N, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			cycles = 3

		elseif opcode == 0x25 then -- AND zpg
			local addr = AddrZeroPage(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 3

		elseif opcode == 0x26 then -- ROL zpg
			local addr = AddrZeroPage(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.bor(bit32.lshift(val, 1), oldC), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 5

		elseif opcode == 0x28 then -- PLP
			local p = PullByte(data)
			p = bit32.band(p, bit32.bnot(bit32.lshift(1, FLAG_B)))
			p = bit32.bor(p, bit32.lshift(1, FLAG_U))
			WriteP(data, p)
			cycles = 4

		elseif opcode == 0x29 then -- AND imm
			local addr = AddrImmediate(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 2

		elseif opcode == 0x2A then -- ROL A
			local a = ReadA(data)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, if bit32.band(a, 0x80) ~= 0 then 1 else 0)
			a = bit32.band(bit32.bor(bit32.lshift(a, 1), oldC), 0xFF)
			WriteA(data, a)
			SetZN(data, a)
			cycles = 2

		elseif opcode == 0x2C then -- BIT abs
			local addr = AddrAbsolute(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_Z, if bit32.band(ReadA(data), val) == 0 then 1 else 0)
			SetFlag(data, FLAG_V, if bit32.band(val, 0x40) ~= 0 then 1 else 0)
			SetFlag(data, FLAG_N, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			cycles = 4

		elseif opcode == 0x2D then -- AND abs
			local addr = AddrAbsolute(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4

		elseif opcode == 0x2E then -- ROL abs
			local addr = AddrAbsolute(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.bor(bit32.lshift(val, 1), oldC), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x30 then -- BMI
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_N) == 1 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0x31 then -- AND (ind),Y
			local addr, pg = AddrIndirectY(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 5 + (if pg then 1 else 0)

		elseif opcode == 0x35 then -- AND zpg,X
			local addr = AddrZeroPageX(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4

		elseif opcode == 0x36 then -- ROL zpg,X
			local addr = AddrZeroPageX(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.bor(bit32.lshift(val, 1), oldC), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x38 then -- SEC
			SetFlag(data, FLAG_C, 1)
			cycles = 2

		elseif opcode == 0x39 then -- AND abs,Y
			local addr, pg = AddrAbsoluteY(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x3D then -- AND abs,X
			local addr, pg = AddrAbsoluteX(data)
			local result = bit32.band(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x3E then -- ROL abs,X
			local addr = AddrAbsoluteX(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, if bit32.band(val, 0x80) ~= 0 then 1 else 0)
			val = bit32.band(bit32.bor(bit32.lshift(val, 1), oldC), 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 7

		elseif opcode == 0x40 then -- RTI
			local p = PullByte(data)
			p = bit32.band(p, bit32.bnot(bit32.lshift(1, FLAG_B)))
			p = bit32.bor(p, bit32.lshift(1, FLAG_U))
			WriteP(data, p)
			WritePC(data, PullWord(data))
			cycles = 6

		elseif opcode == 0x41 then -- EOR (ind,X)
			local addr = AddrIndirectX(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 6

		elseif opcode == 0x45 then -- EOR zpg
			local addr = AddrZeroPage(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 3

		elseif opcode == 0x46 then -- LSR zpg
			local addr = AddrZeroPage(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.rshift(val, 1)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 5

		elseif opcode == 0x48 then -- PHA
			PushByte(data, ReadA(data))
			cycles = 3

		elseif opcode == 0x49 then -- EOR imm
			local addr = AddrImmediate(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 2

		elseif opcode == 0x4A then -- LSR A
			local a = ReadA(data)
			SetFlag(data, FLAG_C, bit32.band(a, 0x01))
			a = bit32.rshift(a, 1)
			WriteA(data, a)
			SetZN(data, a)
			cycles = 2

		elseif opcode == 0x4C then -- JMP abs
			WritePC(data, AddrAbsolute(data))
			cycles = 3

		elseif opcode == 0x4D then -- EOR abs
			local addr = AddrAbsolute(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4

		elseif opcode == 0x4E then -- LSR abs
			local addr = AddrAbsolute(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.rshift(val, 1)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x50 then -- BVC
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_V) == 0 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0x51 then -- EOR (ind),Y
			local addr, pg = AddrIndirectY(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 5 + (if pg then 1 else 0)

		elseif opcode == 0x55 then -- EOR zpg,X
			local addr = AddrZeroPageX(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4

		elseif opcode == 0x56 then -- LSR zpg,X
			local addr = AddrZeroPageX(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.rshift(val, 1)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x58 then -- CLI
			SetFlag(data, FLAG_I, 0)
			cycles = 2

		elseif opcode == 0x59 then -- EOR abs,Y
			local addr, pg = AddrAbsoluteY(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x5D then -- EOR abs,X
			local addr, pg = AddrAbsoluteX(data)
			local result = bit32.bxor(ReadA(data), MemRead(data, addr))
			WriteA(data, result)
			SetZN(data, result)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x5E then -- LSR abs,X
			local addr = AddrAbsoluteX(data)
			local val = MemRead(data, addr)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.rshift(val, 1)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 7

		elseif opcode == 0x60 then -- RTS
			WritePC(data, PullWord(data) + 1)
			cycles = 6

		elseif opcode == 0x61 then -- ADC (ind,X)
			DoADC(data, MemRead(data, AddrIndirectX(data)))
			cycles = 6

		elseif opcode == 0x65 then -- ADC zpg
			DoADC(data, MemRead(data, AddrZeroPage(data)))
			cycles = 3

		elseif opcode == 0x66 then -- ROR zpg
			local addr = AddrZeroPage(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.bor(bit32.rshift(val, 1), bit32.lshift(oldC, 7))
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 5

		elseif opcode == 0x68 then -- PLA
			local a = PullByte(data)
			WriteA(data, a)
			SetZN(data, a)
			cycles = 4

		elseif opcode == 0x69 then -- ADC imm
			DoADC(data, MemRead(data, AddrImmediate(data)))
			cycles = 2

		elseif opcode == 0x6A then -- ROR A
			local a = ReadA(data)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, bit32.band(a, 0x01))
			a = bit32.bor(bit32.rshift(a, 1), bit32.lshift(oldC, 7))
			WriteA(data, a)
			SetZN(data, a)
			cycles = 2

		elseif opcode == 0x6C then -- JMP (ind)
			local pcNow = ReadPC(data)
			local ptr = MemRead16(data, pcNow)
			WritePC(data, MemRead16Bug(data, ptr))
			cycles = 5

		elseif opcode == 0x6D then -- ADC abs
			DoADC(data, MemRead(data, AddrAbsolute(data)))
			cycles = 4

		elseif opcode == 0x6E then -- ROR abs
			local addr = AddrAbsolute(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.bor(bit32.rshift(val, 1), bit32.lshift(oldC, 7))
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x70 then -- BVS
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_V) == 1 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0x71 then -- ADC (ind),Y
			local addr, pg = AddrIndirectY(data)
			DoADC(data, MemRead(data, addr))
			cycles = 5 + (if pg then 1 else 0)

		elseif opcode == 0x75 then -- ADC zpg,X
			DoADC(data, MemRead(data, AddrZeroPageX(data)))
			cycles = 4

		elseif opcode == 0x76 then -- ROR zpg,X
			local addr = AddrZeroPageX(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.bor(bit32.rshift(val, 1), bit32.lshift(oldC, 7))
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0x78 then -- SEI
			SetFlag(data, FLAG_I, 1)
			cycles = 2

		elseif opcode == 0x79 then -- ADC abs,Y
			local addr, pg = AddrAbsoluteY(data)
			DoADC(data, MemRead(data, addr))
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x7D then -- ADC abs,X
			local addr, pg = AddrAbsoluteX(data)
			DoADC(data, MemRead(data, addr))
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0x7E then -- ROR abs,X
			local addr = AddrAbsoluteX(data)
			local val = MemRead(data, addr)
			local oldC = GetFlag(data, FLAG_C)
			SetFlag(data, FLAG_C, bit32.band(val, 0x01))
			val = bit32.bor(bit32.rshift(val, 1), bit32.lshift(oldC, 7))
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 7

		elseif opcode == 0x81 then -- STA (ind,X)
			MemWrite(data, AddrIndirectX(data), ReadA(data))
			cycles = 6

		elseif opcode == 0x84 then -- STY zpg
			MemWrite(data, AddrZeroPage(data), ReadY(data))
			cycles = 3

		elseif opcode == 0x85 then -- STA zpg
			MemWrite(data, AddrZeroPage(data), ReadA(data))
			cycles = 3

		elseif opcode == 0x86 then -- STX zpg
			MemWrite(data, AddrZeroPage(data), ReadX(data))
			cycles = 3

		elseif opcode == 0x88 then -- DEY
			local y = bit32.band(ReadY(data) - 1, 0xFF)
			WriteY(data, y)
			SetZN(data, y)
			cycles = 2

		elseif opcode == 0x8A then -- TXA
			local a = ReadX(data)
			WriteA(data, a)
			SetZN(data, a)
			cycles = 2

		elseif opcode == 0x8C then -- STY abs
			MemWrite(data, AddrAbsolute(data), ReadY(data))
			cycles = 4

		elseif opcode == 0x8D then -- STA abs
			MemWrite(data, AddrAbsolute(data), ReadA(data))
			cycles = 4

		elseif opcode == 0x8E then -- STX abs
			MemWrite(data, AddrAbsolute(data), ReadX(data))
			cycles = 4

		elseif opcode == 0x90 then -- BCC
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_C) == 0 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0x91 then -- STA (ind),Y
			local addr = AddrIndirectY(data)
			MemWrite(data, addr, ReadA(data))
			cycles = 6

		elseif opcode == 0x94 then -- STY zpg,X
			MemWrite(data, AddrZeroPageX(data), ReadY(data))
			cycles = 4

		elseif opcode == 0x95 then -- STA zpg,X
			MemWrite(data, AddrZeroPageX(data), ReadA(data))
			cycles = 4

		elseif opcode == 0x96 then -- STX zpg,Y
			MemWrite(data, AddrZeroPageY(data), ReadX(data))
			cycles = 4

		elseif opcode == 0x98 then -- TYA
			local a = ReadY(data)
			WriteA(data, a)
			SetZN(data, a)
			cycles = 2

		elseif opcode == 0x99 then -- STA abs,Y
			local addr = AddrAbsoluteY(data)
			MemWrite(data, addr, ReadA(data))
			cycles = 5

		elseif opcode == 0x9A then -- TXS
			WriteSP(data, ReadX(data))
			cycles = 2

		elseif opcode == 0x9D then -- STA abs,X
			local addr = AddrAbsoluteX(data)
			MemWrite(data, addr, ReadA(data))
			cycles = 5

		elseif opcode == 0xA0 then -- LDY imm
			local val = MemRead(data, AddrImmediate(data))
			WriteY(data, val)
			SetZN(data, val)
			cycles = 2

		elseif opcode == 0xA1 then -- LDA (ind,X)
			local val = MemRead(data, AddrIndirectX(data))
			WriteA(data, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0xA2 then -- LDX imm
			local val = MemRead(data, AddrImmediate(data))
			WriteX(data, val)
			SetZN(data, val)
			cycles = 2

		elseif opcode == 0xA4 then -- LDY zpg
			local val = MemRead(data, AddrZeroPage(data))
			WriteY(data, val)
			SetZN(data, val)
			cycles = 3

		elseif opcode == 0xA5 then -- LDA zpg
			local val = MemRead(data, AddrZeroPage(data))
			WriteA(data, val)
			SetZN(data, val)
			cycles = 3

		elseif opcode == 0xA6 then -- LDX zpg
			local val = MemRead(data, AddrZeroPage(data))
			WriteX(data, val)
			SetZN(data, val)
			cycles = 3

		elseif opcode == 0xA8 then -- TAY
			local y = ReadA(data)
			WriteY(data, y)
			SetZN(data, y)
			cycles = 2

		elseif opcode == 0xA9 then -- LDA imm
			local val = MemRead(data, AddrImmediate(data))
			WriteA(data, val)
			SetZN(data, val)
			cycles = 2

		elseif opcode == 0xAA then -- TAX
			local x = ReadA(data)
			WriteX(data, x)
			SetZN(data, x)
			cycles = 2

		elseif opcode == 0xAC then -- LDY abs
			local val = MemRead(data, AddrAbsolute(data))
			WriteY(data, val)
			SetZN(data, val)
			cycles = 4

		elseif opcode == 0xAD then -- LDA abs
			local val = MemRead(data, AddrAbsolute(data))
			WriteA(data, val)
			SetZN(data, val)
			cycles = 4

		elseif opcode == 0xAE then -- LDX abs
			local val = MemRead(data, AddrAbsolute(data))
			WriteX(data, val)
			SetZN(data, val)
			cycles = 4

		elseif opcode == 0xB0 then -- BCS
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_C) == 1 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0xB1 then -- LDA (ind),Y
			local addr, pg = AddrIndirectY(data)
			local val = MemRead(data, addr)
			WriteA(data, val)
			SetZN(data, val)
			cycles = 5 + (if pg then 1 else 0)

		elseif opcode == 0xB4 then -- LDY zpg,X
			local val = MemRead(data, AddrZeroPageX(data))
			WriteY(data, val)
			SetZN(data, val)
			cycles = 4

		elseif opcode == 0xB5 then -- LDA zpg,X
			local val = MemRead(data, AddrZeroPageX(data))
			WriteA(data, val)
			SetZN(data, val)
			cycles = 4

		elseif opcode == 0xB6 then -- LDX zpg,Y
			local val = MemRead(data, AddrZeroPageY(data))
			WriteX(data, val)
			SetZN(data, val)
			cycles = 4

		elseif opcode == 0xB8 then -- CLV
			SetFlag(data, FLAG_V, 0)
			cycles = 2

		elseif opcode == 0xB9 then -- LDA abs,Y
			local addr, pg = AddrAbsoluteY(data)
			local val = MemRead(data, addr)
			WriteA(data, val)
			SetZN(data, val)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xBA then -- TSX
			local x = ReadSP(data)
			WriteX(data, x)
			SetZN(data, x)
			cycles = 2

		elseif opcode == 0xBC then -- LDY abs,X
			local addr, pg = AddrAbsoluteX(data)
			local val = MemRead(data, addr)
			WriteY(data, val)
			SetZN(data, val)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xBD then -- LDA abs,X
			local addr, pg = AddrAbsoluteX(data)
			local val = MemRead(data, addr)
			WriteA(data, val)
			SetZN(data, val)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xBE then -- LDX abs,Y
			local addr, pg = AddrAbsoluteY(data)
			local val = MemRead(data, addr)
			WriteX(data, val)
			SetZN(data, val)
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xC0 then -- CPY imm
			DoCMP(data, ReadY(data), MemRead(data, AddrImmediate(data)))
			cycles = 2

		elseif opcode == 0xC1 then -- CMP (ind,X)
			DoCMP(data, ReadA(data), MemRead(data, AddrIndirectX(data)))
			cycles = 6

		elseif opcode == 0xC4 then -- CPY zpg
			DoCMP(data, ReadY(data), MemRead(data, AddrZeroPage(data)))
			cycles = 3

		elseif opcode == 0xC5 then -- CMP zpg
			DoCMP(data, ReadA(data), MemRead(data, AddrZeroPage(data)))
			cycles = 3

		elseif opcode == 0xC6 then -- DEC zpg
			local addr = AddrZeroPage(data)
			local val = bit32.band(MemRead(data, addr) - 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 5

		elseif opcode == 0xC8 then -- INY
			local y = bit32.band(ReadY(data) + 1, 0xFF)
			WriteY(data, y)
			SetZN(data, y)
			cycles = 2

		elseif opcode == 0xC9 then -- CMP imm
			DoCMP(data, ReadA(data), MemRead(data, AddrImmediate(data)))
			cycles = 2

		elseif opcode == 0xCA then -- DEX
			local x = bit32.band(ReadX(data) - 1, 0xFF)
			WriteX(data, x)
			SetZN(data, x)
			cycles = 2

		elseif opcode == 0xCC then -- CPY abs
			DoCMP(data, ReadY(data), MemRead(data, AddrAbsolute(data)))
			cycles = 4

		elseif opcode == 0xCD then -- CMP abs
			DoCMP(data, ReadA(data), MemRead(data, AddrAbsolute(data)))
			cycles = 4

		elseif opcode == 0xCE then -- DEC abs
			local addr = AddrAbsolute(data)
			local val = bit32.band(MemRead(data, addr) - 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0xD0 then -- BNE
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_Z) == 0 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0xD1 then -- CMP (ind),Y
			local addr, pg = AddrIndirectY(data)
			DoCMP(data, ReadA(data), MemRead(data, addr))
			cycles = 5 + (if pg then 1 else 0)

		elseif opcode == 0xD5 then -- CMP zpg,X
			DoCMP(data, ReadA(data), MemRead(data, AddrZeroPageX(data)))
			cycles = 4

		elseif opcode == 0xD6 then -- DEC zpg,X
			local addr = AddrZeroPageX(data)
			local val = bit32.band(MemRead(data, addr) - 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0xD8 then -- CLD
			SetFlag(data, FLAG_D, 0)
			cycles = 2

		elseif opcode == 0xD9 then -- CMP abs,Y
			local addr, pg = AddrAbsoluteY(data)
			DoCMP(data, ReadA(data), MemRead(data, addr))
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xDD then -- CMP abs,X
			local addr, pg = AddrAbsoluteX(data)
			DoCMP(data, ReadA(data), MemRead(data, addr))
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xDE then -- DEC abs,X
			local addr = AddrAbsoluteX(data)
			local val = bit32.band(MemRead(data, addr) - 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 7

		elseif opcode == 0xE0 then -- CPX imm
			DoCMP(data, ReadX(data), MemRead(data, AddrImmediate(data)))
			cycles = 2

		elseif opcode == 0xE1 then -- SBC (ind,X)
			DoSBC(data, MemRead(data, AddrIndirectX(data)))
			cycles = 6

		elseif opcode == 0xE4 then -- CPX zpg
			DoCMP(data, ReadX(data), MemRead(data, AddrZeroPage(data)))
			cycles = 3

		elseif opcode == 0xE5 then -- SBC zpg
			DoSBC(data, MemRead(data, AddrZeroPage(data)))
			cycles = 3

		elseif opcode == 0xE6 then -- INC zpg
			local addr = AddrZeroPage(data)
			local val = bit32.band(MemRead(data, addr) + 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 5

		elseif opcode == 0xE8 then -- INX
			local x = bit32.band(ReadX(data) + 1, 0xFF)
			WriteX(data, x)
			SetZN(data, x)
			cycles = 2

		elseif opcode == 0xE9 then -- SBC imm
			DoSBC(data, MemRead(data, AddrImmediate(data)))
			cycles = 2

		elseif opcode == 0xEA then -- NOP
			cycles = 2

		elseif opcode == 0xEC then -- CPX abs
			DoCMP(data, ReadX(data), MemRead(data, AddrAbsolute(data)))
			cycles = 4

		elseif opcode == 0xED then -- SBC abs
			DoSBC(data, MemRead(data, AddrAbsolute(data)))
			cycles = 4

		elseif opcode == 0xEE then -- INC abs
			local addr = AddrAbsolute(data)
			local val = bit32.band(MemRead(data, addr) + 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0xF0 then -- BEQ
			local addr = AddrRelative(data)
			cycles = 2
			if GetFlag(data, FLAG_Z) == 1 then
				cycles = DoBranch(data, addr, cycles)
			end

		elseif opcode == 0xF1 then -- SBC (ind),Y
			local addr, pg = AddrIndirectY(data)
			DoSBC(data, MemRead(data, addr))
			cycles = 5 + (if pg then 1 else 0)

		elseif opcode == 0xF5 then -- SBC zpg,X
			DoSBC(data, MemRead(data, AddrZeroPageX(data)))
			cycles = 4

		elseif opcode == 0xF6 then -- INC zpg,X
			local addr = AddrZeroPageX(data)
			local val = bit32.band(MemRead(data, addr) + 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 6

		elseif opcode == 0xF8 then -- SED
			SetFlag(data, FLAG_D, 1)
			cycles = 2

		elseif opcode == 0xF9 then -- SBC abs,Y
			local addr, pg = AddrAbsoluteY(data)
			DoSBC(data, MemRead(data, addr))
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xFD then -- SBC abs,X
			local addr, pg = AddrAbsoluteX(data)
			DoSBC(data, MemRead(data, addr))
			cycles = 4 + (if pg then 1 else 0)

		elseif opcode == 0xFE then -- INC abs,X
			local addr = AddrAbsoluteX(data)
			local val = bit32.band(MemRead(data, addr) + 1, 0xFF)
			MemWrite(data, addr, val)
			SetZN(data, val)
			cycles = 7

		elseif opcode == 0x02 then -- HLT (unofficial)
			WriteHalted(data, 1)
			WritePC(data, ReadPC(data) - 1)
			cycles = 2

		else -- illegal/unimplemented → NOP
			cycles = 2
		end

		WriteCycles(data, ReadCycles(data) + cycles)
		return cycles
	end

	@native @checked function __class.Run(self: MOS6502Instance, TargetCycles: number): number
		local executed = 0
		local step = self.Step
		while executed < TargetCycles do
			local c = step(self)
			if c == 0 then break end
			executed += c
		end
		return executed
	end

	table.freeze(__class)
end

local __meta = table.freeze({ __index = __class })

export type MOS6502Instance = typeof(table.freeze(setmetatable(
	{} :: {
		_data: buffer,
	}, __meta
)))

@native @checked function MOS6502.new(): MOS6502Instance
	local data = buffer.create(BUFFER_SIZE)
	Init(data)
	return table.freeze(setmetatable({
		_data = data,
	}, __meta))
end

return table.freeze(MOS6502)
