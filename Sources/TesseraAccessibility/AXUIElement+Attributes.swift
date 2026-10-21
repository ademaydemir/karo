import ApplicationServices

extension AXUIElement {
    func value(of attribute: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success, let value else {
            throw AccessibilityError.failure(attribute: attribute, code: result)
        }
        return value
    }

    func element(of attribute: String) throws -> AXUIElement {
        let value = try value(of: attribute)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw AccessibilityError.unexpectedValue(attribute: attribute)
        }
        // Checked by type ID above; CF types cannot be conditionally cast.
        return value as! AXUIElement
    }

    func point(of attribute: String) throws -> CGPoint {
        var point = CGPoint.zero
        try unpack(attribute, type: .cgPoint, into: &point)
        return point
    }

    func size(of attribute: String) throws -> CGSize {
        var size = CGSize.zero
        try unpack(attribute, type: .cgSize, into: &size)
        return size
    }

    func setValue(_ value: CFTypeRef, of attribute: String) throws {
        let result = AXUIElementSetAttributeValue(self, attribute as CFString, value)
        guard result == .success else {
            throw AccessibilityError.failure(attribute: attribute, code: result)
        }
    }

    func setPoint(_ point: CGPoint, of attribute: String) throws {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            throw AccessibilityError.unexpectedValue(attribute: attribute)
        }
        try setValue(value, of: attribute)
    }

    func setSize(_ size: CGSize, of attribute: String) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw AccessibilityError.unexpectedValue(attribute: attribute)
        }
        try setValue(value, of: attribute)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(self, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private func unpack<T: BitwiseCopyable>(_ attribute: String, type: AXValueType, into storage: inout T) throws {
        let value = try value(of: attribute)
        guard CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, type, &storage) else {
            throw AccessibilityError.unexpectedValue(attribute: attribute)
        }
    }
}
