import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - shared helpers for the live-data macros
//
// the four macros emit only what the frozen protocols already require, so every
// helper here reads the annotated declaration's SYNTAX and never assumes a type:
// a splice the type checker rejects is the deliberate validation locus (a macro
// sees syntax, not types).

/// the access prefix a generated member carries — a witness for a public type
/// must itself be public.
func accessPrefix(for declaration: some DeclGroupSyntax) -> String {
	declaration.modifiers.contains { $0.name.text == "public" } ? "public " : ""
}

/// every name the declaration already binds (variables and functions), so a
/// macro never emits a duplicate declaration.
func declaredNames(of declaration: some DeclGroupSyntax) -> Set<String> {
	var names: Set<String> = []
	for member in declaration.memberBlock.members {
		if let variable = member.decl.as(VariableDeclSyntax.self) {
			for binding in variable.bindings {
				if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
					names.insert(identifier.identifier.text)
				}
			}
		}
		if let function = member.decl.as(FunctionDeclSyntax.self) {
			names.insert(function.name.text)
		}
	}
	return names
}

/// the value of a single-segment string-literal expression, or nil when the
/// expression is not readable as a literal (an id the macro cannot see).
func stringLiteralValue(_ expression: ExprSyntax) -> String? {
	guard let literal = expression.as(StringLiteralExprSyntax.self),
	      literal.segments.count == 1,
	      let segment = literal.segments.first?.as(StringSegmentSyntax.self)
	else { return nil }
	return segment.content.text
}

/// the base name of a written type: `any LiveState` → `LiveState`,
/// `LiveBox<Int>` → `LiveBox`, `Tick?` → `Tick`.
func baseTypeName(_ type: TypeSyntax) -> String {
	if let optional = type.as(OptionalTypeSyntax.self) { return baseTypeName(optional.wrappedType) }
	if let someOrAny = type.as(SomeOrAnyTypeSyntax.self) { return baseTypeName(someOrAny.constraint) }
	if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
	if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
	return type.trimmedDescription
}

/// the type name a property is written or constructed with: the explicit
/// annotation when present, else the initializer's callee (`Tick(box:)` →
/// `Tick`). nil when neither is determinable — the caller diagnoses that
/// rather than guessing, because guessing silently drops a region.
func candidateTypeName(of binding: PatternBindingSyntax) -> String? {
	if let annotation = binding.typeAnnotation {
		return baseTypeName(annotation.type)
	}
	guard let call = binding.initializer?.value.as(FunctionCallExprSyntax.self) else { return nil }
	if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
		return reference.baseName.text
	}
	if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
		return member.declName.baseName.text
	}
	return nil
}

/// stored, non-static properties in declaration order, with their names.
func storedPropertyNames(of declaration: some DeclGroupSyntax) -> [String] {
	var names: [String] = []
	for member in declaration.memberBlock.members {
		guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
		let isStatic = variable.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
		guard !isStatic else { continue }
		for binding in variable.bindings {
			guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
			names.append(identifier.identifier.text)
		}
	}
	return names
}

/// the stored properties carrying a named marker attribute, in order.
func markedPropertyNames(_ marker: String, in declaration: some DeclGroupSyntax) -> [String] {
	func carriesMarker(_ variable: VariableDeclSyntax) -> Bool {
		for element in variable.attributes {
			guard let attribute = element.as(AttributeSyntax.self) else { continue }
			guard let name = attribute.attributeName.as(IdentifierTypeSyntax.self) else { continue }
			if name.name.text == marker { return true }
		}
		return false
	}
	var names: [String] = []
	for member in declaration.memberBlock.members {
		guard let variable = member.decl.as(VariableDeclSyntax.self), carriesMarker(variable) else { continue }
		for binding in variable.bindings {
			if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
				names.append(identifier.identifier.text)
			}
		}
	}
	return names
}

/// nested type declarations in the group, with the attribute names each carries.
func nestedTypes(in declaration: some DeclGroupSyntax) -> [(name: String, attributes: Set<String>)] {
	func attributes(of list: AttributeListSyntax) -> Set<String> {
		Set(list.compactMap { $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text })
	}
	var found: [(name: String, attributes: Set<String>)] = []
	for member in declaration.memberBlock.members {
		let decl = member.decl
		if let structDecl = decl.as(StructDeclSyntax.self) {
			found.append((structDecl.name.text, attributes(of: structDecl.attributes)))
		} else if let classDecl = decl.as(ClassDeclSyntax.self) {
			found.append((classDecl.name.text, attributes(of: classDecl.attributes)))
		} else if let actorDecl = decl.as(ActorDeclSyntax.self) {
			found.append((actorDecl.name.text, attributes(of: actorDecl.attributes)))
		} else if let enumDecl = decl.as(EnumDeclSyntax.self) {
			found.append((enumDecl.name.text, attributes(of: enumDecl.attributes)))
		}
	}
	return found
}

/// the literal `id:` argument on an attribute, when the macro can read it.
func literalIDArgument(of attribute: AttributeSyntax) -> String? {
	guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else { return nil }
	for argument in arguments where argument.label?.text == "id" {
		return stringLiteralValue(argument.expression)
	}
	return nil
}

/// the `@LiveRegion(id:)` / `@LiveState` attribute on a nested declaration, if present.
func attribute(named name: String, in attributes: Set<String>) -> Bool {
	attributes.contains(name)
}