//
//  LaTeXNormalizerTests.swift
//  CopyShotTests
//
//  Created by Mac on 30.09.26.
//

import Testing
import Foundation
@testable import CopyShot

@Suite("LaTeXNormalizer Tests")
struct LaTeXNormalizerTests {

    @Test("Prettify compacts redundant spacing around braces, operators, and scripts")
    func testPrettifyCompactsSpacing() {
        let input = "2 \\pi \\! \\int _ { a } ^ { b } f ( x ) \\! \\sqrt { 1 + f ^ { \\prime } ( x ) ^ { 2 } } \\, d x"
        let output = LaTeXNormalizer.prettify(input)
        
        #expect(output.contains("_{a}"))
        #expect(output.contains("^{b}"))
        #expect(output.contains("f(x)"))
        #expect(!output.contains("_ {"))
        #expect(!output.contains("^ {"))
        #expect(!output.contains("{ "))
        #expect(!output.contains(" }"))
    }
    
    @Test("Prettify handles powers and subscripts without curly braces")
    func testPrettifySingleCharacterScripts() {
        let input = "x _ 1 ^ 2 + y _ 2 ^ 2 = z _ 3 ^ 2"
        let output = LaTeXNormalizer.prettify(input)
        #expect(output == "x_1^2 + y_2^2 = z_3^2")
    }

    @Test("FixSyntax strips trailing redundant closing bracket")
    func testFixSyntaxTrailingBracket() {
        let broken = "x^2 + y^2 = z^2 }"
        let (fixed, wasFixed) = LaTeXNormalizer.fixSyntax(broken)
        #expect(wasFixed)
        #expect(fixed == "x^2 + y^2 = z^2")
    }

    @Test("FixSyntax appends unclosed curly braces")
    func testFixSyntaxUnclosedBraces() {
        let broken = "\\frac{a + b}{c"
        let (fixed, wasFixed) = LaTeXNormalizer.fixSyntax(broken)
        #expect(wasFixed)
        #expect(fixed == "\\frac{a + b}{c}")
    }

    @Test("FixSyntax balances unmatched \\left with \\right.")
    func testFixSyntaxUnmatchedLeft() {
        let broken = "\\left( \\frac{a}{b}"
        let (fixed, wasFixed) = LaTeXNormalizer.fixSyntax(broken)
        #expect(wasFixed)
        #expect(fixed == "\\left( \\frac{a}{b} \\right.")
    }

    @Test("FixSyntax escapes unescaped percent sign")
    func testFixSyntaxUnescapedPercent() {
        let broken = "100% = 1.0"
        let (fixed, wasFixed) = LaTeXNormalizer.fixSyntax(broken)
        #expect(wasFixed)
        #expect(fixed == "100\\% = 1.0")
    }

    @Test("FixSyntax does not modify already valid syntax")
    func testFixSyntaxValidFormulaUnchanged() {
        let valid = "\\int_{0}^{\\infty} e^{-x} dx = 1"
        let (fixed, wasFixed) = LaTeXNormalizer.fixSyntax(valid)
        #expect(!wasFixed)
        #expect(fixed == valid)
    }
}
