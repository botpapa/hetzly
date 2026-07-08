import XCTest
@testable import Hetzly

final class CIDRValidatorTests: XCTestCase {
    func test_validIPv4() {
        for input in ["10.0.0.0/8", "0.0.0.0/0", "255.255.255.255/32", "192.168.1.0/24", "1.2.3.4/32"] {
            XCTAssertTrue(CIDRValidator.isValid(input), "\(input) should be valid")
        }
    }

    func test_validIPv6() {
        for input in ["::/0", "2001:db8::/32", "fe80::1/64", "::1/128", "2001:db8:0:0:0:0:0:1/128"] {
            XCTAssertTrue(CIDRValidator.isValid(input), "\(input) should be valid")
        }
    }

    func test_invalidCases() {
        let invalid = [
            "10.0.0.0",             // no prefix
            "10.0.0.0/33",          // prefix out of range for IPv4
            "10.0.0/24",            // only 3 octets
            "10.0.0.256/24",        // octet > 255
            "10.0.0.0.0/24",        // 5 octets
            "01.0.0.0/8",           // leading zero
            "gggg::/64",            // invalid hex group
            "::1::2/64",            // two "::" compressions
            "2001:db8::/129",       // prefix out of range for IPv6
            "",                     // empty
            "not-an-address/24",
        ]
        for input in invalid {
            XCTAssertFalse(CIDRValidator.isValid(input), "\(input) should be invalid")
        }
    }

    func test_trimsWhitespace() {
        XCTAssertTrue(CIDRValidator.isValid("  10.0.0.0/8  "))
    }
}

final class PortValidatorTests: XCTestCase {
    func test_validSinglePorts() {
        for input in ["1", "80", "443", "65535"] {
            XCTAssertTrue(PortValidator.isValid(input), "\(input) should be valid")
        }
    }

    func test_validRanges() {
        for input in ["80-85", "1-65535", "1000-1001"] {
            XCTAssertTrue(PortValidator.isValid(input), "\(input) should be valid")
        }
    }

    func test_invalidCases() {
        let invalid = [
            "",
            "0",              // below range
            "65536",          // above range
            "80-70",          // reversed range
            "80-80",          // not strictly increasing
            "80-",
            "-80",
            "abc",
            "80-85-90",       // too many parts
        ]
        for input in invalid {
            XCTAssertFalse(PortValidator.isValid(input), "\(input) should be invalid")
        }
    }

    func test_trimsWhitespace() {
        XCTAssertTrue(PortValidator.isValid("  22  "))
    }
}
