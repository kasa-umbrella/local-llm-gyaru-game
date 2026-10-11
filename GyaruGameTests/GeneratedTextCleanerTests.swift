import Testing
@testable import GyaruGame

/// 実際にモデルが出力した文字列をもとにした整形のテスト
@MainActor
struct GeneratedTextCleanerTests {
    @Test(arguments: [
        ("「締め切り前の作家さんより、ユウキさんのほうがよほど手がかかりますね」  ――澪は赤ペンを動かしながら、静かに目を細めた。",
         "締め切り前の作家さんより、ユウキさんのほうがよほど手がかかりますね"),
        ("「え、マジで？これ甘すぎでウケるんだけど、弟の分も入れたからちょっとだけ…っしょ？」【選択肢】",
         "え、マジで？これ甘すぎでウケるんだけど、弟の分も入れたからちょっとだけ…っしょ？"),
        ("**天宮ひより**：「ねえ、センパイ、今日から一緒に働くんだけど、なんか緊張する…」",
         "ねえ、センパイ、今日から一緒に働くんだけど、なんか緊張する…"),
        ("遅い！もう10分だよ。べ、別に待ってたわけじゃないし。あんたが来ないから心配しただけ。",
         "遅い！もう10分だよ。"),
        ("え、ほんとに？！うれしい。でもちょっと照れる。",
         "え、ほんとに？！うれしい。"),
    ])
    func cleansLine(raw: String, expected: String) {
        #expect(GeneratedTextCleaner.line(raw) == expected)
    }

    @Test func cleansChoices() {
        let raw = """
        1. 大丈夫、緊張するのも自然だよ

        2.「ネイル、ちょっと派手すぎじゃない？」
        ・ユウキ：私も緊張するから、一緒に練習したい。
        4. 余分な行
        """
        #expect(GeneratedTextCleaner.choices(raw, count: 3) == [
            "大丈夫、緊張するのも自然だよ",
            "ネイル、ちょっと派手すぎじゃない？",
            "私も緊張するから、一緒に練習したい。",
        ])
    }

    @Test func plannedTonesAreDistinctGroups() {
        for _ in 0..<20 {
            let tones = Set(ChoiceTone.plannedSet())
            #expect(tones.count == 3)
            #expect(!tones.isDisjoint(with: [.kind, .honest]))
            #expect(!tones.isDisjoint(with: [.teasing, .romantic]))
            #expect(!tones.isDisjoint(with: [.cool, .rude]))
        }
    }
}

@MainActor
struct DuplicateChoiceTests {
    @Test func detectsExactAndNearDuplicates() {
        let choices = [
            "「勘違いじゃないよ。ただ、偶然出会っただけさ。」",
            "「勘違いじゃない。ただ、偶然出会っただけさ。」",
            "ごめん、本当に考えてるの。",
        ].map(GeneratedTextCleaner.choice)
        // 2つ目は1つ目と「よ」の有無と句読点しか違わないので重複扱いにする
        #expect(GeneratedTextCleaner.duplicateIndices(in: choices) == [1])
    }

    @Test func keepsDistinctChoices() {
        let choices = ["え、えっ？ありがとう。", "…お前、誰にあげたの？", "…ただの弁当だ。"]
        #expect(GeneratedTextCleaner.duplicateIndices(in: choices).isEmpty)
    }
}

@MainActor
struct UsableChoiceTests {
    private let line = "えっ、先輩！隣に座るの、マジでウケるっしょ！"

    @Test(arguments: [
        "えっ、先輩！隣に座るの、マジでウケるっしょ！",  // ヒロインのセリフの写し
        "300000000000000000000",                    // 壊れた出力
        "軽くからかう",                               // 指示語の写し
        "あ",                                       // 短すぎる
    ])
    func rejects(_ text: String) {
        #expect(!GeneratedTextCleaner.isUsableChoice(text, heroineLine: line, others: []))
    }

    @Test func acceptsNormalReplyAndRejectsDuplicate() {
        #expect(GeneratedTextCleaner.isUsableChoice("隣でよかった。よろしくね", heroineLine: line, others: []))
        #expect(!GeneratedTextCleaner.isUsableChoice("隣でよかった、よろしくね！", heroineLine: line, others: ["隣でよかった。よろしくね"]))
    }
}
