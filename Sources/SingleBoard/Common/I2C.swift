/*
 SingleBoard - Common

 Copyright (c) 2018 Adam Thayer
 SwiftyGPIO I2C Implementation Copyright (c) 2017 Umberto Raimondi

 Licensed under the MIT license, as follows:

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)
 */

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

import Foundation

public extension BoardI2CEndpoint {
	// Convenience for Data
	func readData(from command: UInt8) -> Data {
		return Data(bytes: self.readByteArray(from: command))
	}

	func writeData(to command: UInt8, value: Data) {
		self.writeByteArray(to: command, value: [UInt8](value))
	}

	func writeData<T: RawRepresentable>(to command: T, value: Data)
		where T.RawValue == UInt8
	{
		self.writeByteArray(to: command.rawValue, value: [UInt8](value))
	}
    
    // Convenience for Command Enums
    func readByte<T: RawRepresentable>(from command: T) -> UInt8
        where T.RawValue == UInt8
    {
        return self.readByte(from: command.rawValue)
    }
    
    func readWord<T: RawRepresentable>(from command: T) -> UInt16
        where T.RawValue == UInt8
    {
        return self.readWord(from: command.rawValue)
    }
    
    func writeByte<T: RawRepresentable>(to command: T, value: UInt8)
        where T.RawValue == UInt8
    {
        return self.writeByte(to: command.rawValue, value: value)
    }
    
    func writeWord<T: RawRepresentable>(to command: T, value: UInt16)
        where T.RawValue == UInt8
    {
        return self.writeWord(to: command.rawValue, value: value)
    }
    
	// Read in Enums and OptionSets
	func read<T: RawRepresentable, U: RawRepresentable>(from command: T) -> U?
		where T.RawValue == UInt8, U.RawValue == UInt8
	{
		return U(rawValue: self.readByte(from: command.rawValue))
	}

	func read<T: RawRepresentable, U: RawRepresentable>(from command: T) -> U?
		where T.RawValue == UInt8, U.RawValue == UInt16
	{
		return U(rawValue: self.readWord(from: command.rawValue))
	}

	func read<T: RawRepresentable, U: OptionSet>(from command: T) -> U
		where T.RawValue == UInt8, U.RawValue == UInt8
	{
		return U(rawValue: self.readByte(from: command.rawValue))
	}

	func read<T: RawRepresentable, U: OptionSet>(from command: T) -> U
		where T.RawValue == UInt8, U.RawValue == UInt16
	{
		return U(rawValue: self.readWord(from: command.rawValue))
	}

	// Write Enums and OptionSets
	func write<T: RawRepresentable, U: RawRepresentable>(to command: T, value: U)
		where T.RawValue == UInt8, U.RawValue == UInt8
	{
		return self.writeByte(to: command.rawValue, value: value.rawValue)
	}

	func write<T: RawRepresentable, U: RawRepresentable>(to command: T, value: U)
		where T.RawValue == UInt8, U.RawValue == UInt16
	{
		return self.writeWord(to: command.rawValue, value: value.rawValue)
	}
}

extension Dictionary: BoardI2C where Key == Int, Value == BoardI2CChannel {}

public final class SysI2CController: BoardI2CChannel {
	private static let I2C_SLAVE: UInt = 0x703
	private static let I2C_SLAVE_FORCE: UInt = 0x706
	private static let I2C_RDWR: UInt = 0x707
	private static let I2C_PEC: UInt = 0x708
	private static let I2C_SMBUS: UInt = 0x720
	private static let I2C_MAX_LENGTH: Int = 32

	private let channel: Int
	private var fdI2C: Int32 = -1
	private var currentEndpoint: Int?
	private var activeEndpoints: [Int: BoardI2CEndpoint] = [:]

	public init(channel: Int) {
		self.channel = channel
	}

	deinit {
		if fdI2C != -1 {
			close(fdI2C)
		}
	}

	public func isReachable(address: Int) -> Bool {
		return self[address].reachable
	}

	public subscript(address: Int) -> BoardI2CEndpoint {
		if let endpoint = self.activeEndpoints[address] {
			return endpoint
		}

		let endpoint = SysI2CEndpoint(address: address, controller: self)
		self.activeEndpoints[address] = endpoint
		return endpoint
	}

	fileprivate func openChannel() {
		let filePath: String = "/dev/i2c-\(self.channel)"

		let fdI2C = open(filePath, O_RDWR)
		guard fdI2C > 0 else {
			fatalError()
		}

		self.fdI2C = fdI2C
	}

	fileprivate func setCurrentEndpoint(to address: Int) {
		if self.fdI2C == -1 {
			self.openChannel()
		}

		guard self.currentEndpoint != address else { return }

		let result = ioctl(fdI2C, SysI2CController.I2C_SLAVE_FORCE, CInt(address))
		guard result == 0 else {
			fatalError()
		}

		self.currentEndpoint = address
	}

	// MARK: Read/Write Data
	fileprivate func readByte(from command: UInt8) -> UInt8? {
		var data = [UInt8](repeating:0, count: SysI2CController.I2C_MAX_LENGTH+1)

		guard smbusIoctl(.read, command: command, size: MemoryLayout<UInt8>.size, data: &data) else { return nil }
		return data[0]
	}

	fileprivate func readWord(from command: UInt8) -> UInt16? {
		var data = [UInt8](repeating:0, count: SysI2CController.I2C_MAX_LENGTH+1)

		guard smbusIoctl(.read, command: command, size: MemoryLayout<UInt16>.size, data: &data) else { return nil }
		return (UInt16(data[1]) << 8) + UInt16(data[0])
	}

	fileprivate func readByteArray(from command: UInt8) -> [UInt8]? {
		var data = [UInt8](repeating:0, count: SysI2CController.I2C_MAX_LENGTH+1)

		guard smbusIoctl(.read, command: command, size: 5, data: &data) else { return nil }
		let lenData = Int(data[0])
		return Array(data[1...lenData])
	}

	fileprivate func writeQuick() -> Bool {
		return smbusIoctl(.write, command: 0, size: 0, data: nil)
	}

	fileprivate func writeByte(value: UInt8) -> Bool {
		return  smbusIoctl(.write, command: value, size: MemoryLayout<UInt8>.size, data: nil)
	}

	fileprivate func writeByte(to command: UInt8, value: UInt8) -> Bool {
		var data = [UInt8](repeating:0, count: SysI2CController.I2C_MAX_LENGTH+1)

		data[0] = value
		guard smbusIoctl(.write, command: command, size: MemoryLayout<UInt8>.size, data: &data) else { return false }
		return true
	}

	fileprivate func writeWord(to command: UInt8, value: UInt16) -> Bool {
		var data = [UInt8](repeating:0, count: SysI2CController.I2C_MAX_LENGTH+1)

		data[0] = UInt8(value & 0xFF)
		data[1] = UInt8(value >> 8)
		guard smbusIoctl(.write, command: command, size: MemoryLayout<UInt16>.size, data: &data) else { return false }
		return true
	}

	fileprivate func writeByteArray(to command: UInt8, value: [UInt8]) -> Bool {
		guard value.count <= SysI2CController.I2C_MAX_LENGTH else { return false }
		var data = [UInt8](repeating:0, count: SysI2CController.I2C_MAX_LENGTH+1)

		for i in 1...value.count {
			data[i] = value[i - 1]
		}
		data[0] = UInt8(value.count)
		guard smbusIoctl(.write, command: command, size: 5, data: &data) else { return false }
		return true
	}

	fileprivate func smbusIoctl(_ readOrWrite: SMBusReadWrite, command: UInt8, size: Int, data: UnsafeMutablePointer<UInt8>?) -> Bool {
		if self.fdI2C == -1 {
			self.openChannel()
		}

		var args = SMBusData(readOrWrite: readOrWrite, command: command, size: Int32(size), data: data)
		return ioctl(self.fdI2C, SysI2CController.I2C_SMBUS, &args) >= 0
	}
}

public final class SysI2CEndpoint: BoardI2CEndpoint {
	private let address: Int
	private let controller: SysI2CController

	init(address: Int, controller: SysI2CController) {
		self.address = address
		self.controller = controller
	}

	public var reachable: Bool {
		controller.setCurrentEndpoint(to: address)

		return false
	}

	public func readByte() -> UInt8 {
		controller.setCurrentEndpoint(to: address)

		guard let byte = controller.readByte(from: 0) else { fatalError() }
		return byte
	}

	public func readByte(from command: UInt8) -> UInt8 {
		controller.setCurrentEndpoint(to: address)

		guard let byte = controller.readByte(from: command) else { fatalError() }
		return byte
	}

	public func readWord(from command: UInt8) -> UInt16 {
		controller.setCurrentEndpoint(to: address)

		guard let word = controller.readWord(from: command) else { fatalError() }
		return word
	}

	public func readByteArray(from command: UInt8) -> [UInt8] {
		controller.setCurrentEndpoint(to: address)

		guard let byteArray = controller.readByteArray(from: command) else { fatalError() }
		return byteArray
	}

	public func writeQuick() {
		controller.setCurrentEndpoint(to: address)

		guard controller.writeQuick() else { fatalError() }
	}

	public func writeByte(value: UInt8) {
		controller.setCurrentEndpoint(to: address)

		guard controller.writeByte(value: value) else { fatalError() }
	}

	public func writeByte(to command: UInt8, value: UInt8) {
		controller.setCurrentEndpoint(to: address)

		guard controller.writeByte(to: command, value: value) else { fatalError() }
	}

	public func writeWord(to command: UInt8, value: UInt16) {
		controller.setCurrentEndpoint(to: address)

		guard controller.writeWord(to: command, value: value) else { fatalError() }
	}

	public func writeByteArray(to command: UInt8, value: [UInt8]) {
		controller.setCurrentEndpoint(to: address)

		guard controller.writeByteArray(to: command, value: value) else { fatalError() }
	}
}

struct SMBusReadWrite {
	let rawValue: UInt8

	private init(rawValue: UInt8) {
		self.rawValue = rawValue
	}

	static let read = SMBusReadWrite(rawValue: 0)
	static let write = SMBusReadWrite(rawValue: 1)
}

fileprivate struct SMBusData {
	var readOrWrite: SMBusReadWrite
	var command: UInt8
	var size: Int32
	var data: UnsafeMutablePointer<UInt8>?
}