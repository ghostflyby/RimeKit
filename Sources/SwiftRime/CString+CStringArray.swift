#if canImport(Darwin)
	import Darwin
#endif
#if canImport(Glibc)
	import Glibc
#endif

/// A property wrapper that projects a Swift String to a C string (null-terminated `char*`).
///
/// The C string lives as long as the wrapper instance lives.
@propertyWrapper
struct CString: ~Copyable {
	var projectedValue: UnsafePointer<CChar>
	var wrappedValue: String {
		didSet {
			projectedValue.deallocate()
			projectedValue = UnsafePointer(strdup(wrappedValue))
		}
	}

	init(wrappedValue: String) {
		self.wrappedValue = wrappedValue
		self.projectedValue = UnsafePointer(strdup(wrappedValue))
	}

	deinit {
		projectedValue.deallocate()
	}
}

/// A property wrapper that projects a Swift array of Strings to an array of C strings (null-terminated `char**`).
///
/// The C strings live as long as the wrapper instance lives.
@propertyWrapper
struct CStringArray: ~Copyable {
	var projectedValue: UnsafeMutablePointer<UnsafePointer<CChar>?>
	var wrappedValue: [String] {
		didSet {
			for i in 0..<wrappedValue.count {
				projectedValue[i]?.deallocate()
			}
			projectedValue.deallocate()
			projectedValue = CStringArray.createPointer(from: wrappedValue)
		}
	}

	init(wrappedValue: [String]) {
		self.wrappedValue = wrappedValue
		self.projectedValue = CStringArray.createPointer(from: wrappedValue)
	}

	deinit {
		projectedValue.deallocate()
	}

	private static func createPointer(from array: [String]) -> UnsafeMutablePointer<
		UnsafePointer<CChar>?
	> {
		let count = array.count
		let pointer = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: count + 1)
		for (i, str) in array.enumerated() {
			pointer[i] = UnsafePointer(strdup(str))
		}
		pointer[count] = nil
		return pointer
	}
    
    static func convertCStringArrayNullTerminated(_ cArray: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> [String] {
        guard let cArray = cArray else { return [] }
        var result: [String] = []
        var index = 0
        while let cString = cArray[index] {
            result.append(String(cString: cString))
            index += 1
        }
        return result
    }

}
