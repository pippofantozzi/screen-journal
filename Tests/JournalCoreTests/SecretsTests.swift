import Testing
@testable import JournalCore

struct SecretsTests {
    @Test func blanksKeysAndTokens() {
        let cases = [
            "export KEY=sk-proj-abcdefghij1234567890XYZ",
            "vck_ABCDEFGHIJKLMNOP1234",
            "token ghp_abcdefghijklmnopqrstuvwxyz123456",
            "AKIAABCDEFGHIJKLMNOP",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
        ]
        for text in cases {
            #expect(Secrets.redact(text).contains(Secrets.placeholder), "\(text)")
            #expect(!Secrets.redact(text).contains("abcdefghij"))
        }
    }

    @Test func leavesIdsAndHashesForAutomationsToMatch() {
        let text = "commit 9f8e7d6c5b4a39281706f5e4d3c2b1a0aa12bc34 order 3fa85f64-5717-4562-b3fc-2c963f66afa6"
        #expect(Secrets.redact(text) == text)
    }

    @Test func leavesOrdinaryTextPathsAndUrls() {
        let text = """
        ~/Code/forgia-apps/Verify/src/components/AccordionLayout.tsx
        https://vercel.com/forgia/verify/settings/environment-variables
        Internationalization configuration settings
        Invoice 2026-10-21 total R$ 1.234,56
        """
        #expect(Secrets.redact(text) == text)
    }

    @Test func blanksBearerTokensOtpCodesCardsAndValidCpfs() {
        let bearer = "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345"
        #expect(Secrets.redact(bearer) == "Authorization: Bearer [redacted]")

        let otpEN = "Your verification code: 482910"
        #expect(Secrets.redact(otpEN) == "Your verification code: [redacted]")

        let otpPT = "Seu código de verificação é 739104"
        #expect(Secrets.redact(otpPT) == "Seu código de verificação é [redacted]")

        // Synthetic Luhn-valid test card (standard test Visa number)
        let card = "Card 4111 1111 1111 1111 expires 12/29"
        #expect(Secrets.redact(card) == "Card [redacted] expires 12/29")

        // Synthetic check-digit-valid Brazilian CPF (123.456.789-09)
        let cpf = "CPF 123.456.789-09 confirmado"
        #expect(Secrets.redact(cpf) == "CPF [redacted] confirmado")
    }

    @Test func leavesInvalidCardsInvalidCpfsAndPhoneNumbersAlone() {
        let text = "Phone 55 11 98765-4321 ref 4111 1111 1111 1112 cpf 123.456.789-00 id 0000-0000-0000-0000"
        #expect(Secrets.redact(text) == text)
    }
}
