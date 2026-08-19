import Foundation
import Testing
@testable import WhisperDrop

struct AudioExtractorTests {
    @Test func parsesMultipleFFmpegAudioTracksInOrder() {
        let metadata = """
          Stream #0:0: Video: h264, yuv420p
          Stream #0:1[0x1100](rus): Audio: ac3, 48000 Hz, stereo, fltp, 192 kb/s (default)
          Stream #0:2[0x1101](kor): Audio: aac (LC), 48000 Hz, stereo, fltp, 192 kb/s
        """

        let tracks = AudioExtractor.parseAudioTracks(from: metadata)

        #expect(tracks.count == 2)
        #expect(tracks[0].id == 0)
        #expect(tracks[0].languageCode == "rus")
        #expect(tracks[0].codec == "ac3")
        #expect(tracks[0].details.contains("AC-3"))
        #expect(tracks[0].details.contains("48 kHz"))
        #expect(tracks[1].id == 1)
        #expect(tracks[1].languageCode == "kor")
        #expect(tracks[1].codec == "aac (LC)")
        #expect(tracks[1].details.contains("AAC"))
    }

    @Test func ffmpegDownmixesMultichannelAudioForCoreAudioCompatibility() {
        let arguments = AudioExtractor.ffmpegArguments(
            source: URL(fileURLWithPath: "/tmp/source.mkv"),
            output: URL(fileURLWithPath: "/tmp/output.m4a"),
            audioTrackIndex: 2
        )

        let command = arguments.joined(separator: " ")
        #expect(command.contains("-map 0:a:2"))
        #expect(command.contains("-ac 2"))
        #expect(command.contains("-ar 48000"))
        #expect(command.contains("-movflags +faststart"))
    }
}
