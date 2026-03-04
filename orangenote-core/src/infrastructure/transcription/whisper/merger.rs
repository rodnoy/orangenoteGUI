//! Transcription result merger
//!
//! This module handles merging transcription results from multiple audio chunks,
//! including timestamp adjustment and deduplication of overlapping segments.

use super::context::{Segment, TranscriptionResult};
use log::{debug, info};
use std::collections::{HashMap, HashSet};

/// Configuration for merging transcription results
#[derive(Debug, Clone)]
pub struct MergeConfig {
    /// Overlap duration in milliseconds
    pub overlap_ms: i64,
    /// Minimum text similarity threshold for duplicate detection (0.0 - 1.0)
    pub similarity_threshold: f64,
    /// Maximum time difference (ms) to consider segments as potential duplicates
    pub max_time_diff_ms: i64,
    /// Prefer higher confidence segments when deduplicating
    pub prefer_higher_confidence: bool,
}

impl Default for MergeConfig {
    fn default() -> Self {
        MergeConfig {
            overlap_ms: 5000, // 5 seconds
            similarity_threshold: 0.6,
            max_time_diff_ms: 10000, // 10 seconds
            prefer_higher_confidence: true,
        }
    }
}

impl MergeConfig {
    /// Create a new merge config from overlap in seconds
    pub fn from_overlap_secs(overlap_secs: u32) -> Self {
        MergeConfig {
            overlap_ms: (overlap_secs as i64) * 1000,
            ..Default::default()
        }
    }
}

/// Result of merging operation with statistics
#[derive(Debug, Clone)]
pub struct MergeResult {
    /// The merged transcription result
    pub result: TranscriptionResult,
    /// Number of segments before deduplication
    pub total_segments_before: usize,
    /// Number of duplicate segments removed
    pub duplicates_removed: usize,
    /// Number of chunks merged
    pub chunks_merged: usize,
}

/// Merge transcription results from multiple chunks
///
/// # Arguments
///
/// * `results` - Vector of (TranscriptionResult, start_offset_ms) pairs
/// * `config` - Merge configuration
///
/// # Returns
///
/// `MergeResult` containing the merged transcription and statistics
pub fn merge_transcription_results(
    results: Vec<(TranscriptionResult, i64)>,
    config: MergeConfig,
) -> MergeResult {
    if results.is_empty() {
        return MergeResult {
            result: TranscriptionResult {
                language: "unknown".to_string(),
                segments: vec![],
            },
            total_segments_before: 0,
            duplicates_removed: 0,
            chunks_merged: 0,
        };
    }

    let chunks_merged = results.len();

    // Step 1: Determine the most common language
    let language = determine_language(&results);

    // Step 2: Collect all segments with adjusted timestamps
    let mut all_segments: Vec<SegmentWithMeta> = Vec::new();

    for (chunk_idx, (result, start_offset_ms)) in results.into_iter().enumerate() {
        for segment in result.segments {
            all_segments.push(SegmentWithMeta {
                segment: Segment {
                    id: 0, // Will be reassigned later
                    start_ms: segment.start_ms + start_offset_ms,
                    end_ms: segment.end_ms + start_offset_ms,
                    text: segment.text,
                    confidence: segment.confidence,
                    tokens: segment.tokens,
                },
                chunk_index: chunk_idx,
                _original_start_ms: segment.start_ms,
            });
        }
    }

    let total_segments_before = all_segments.len();

    // Step 3: Sort by start time
    all_segments.sort_by_key(|s| s.segment.start_ms);

    // Step 4: Deduplicate overlapping segments
    let deduped_segments = deduplicate_segments(all_segments, &config);
    let duplicates_removed = total_segments_before - deduped_segments.len();

    // Step 5: Reassign sequential IDs
    let final_segments: Vec<Segment> = deduped_segments
        .into_iter()
        .enumerate()
        .map(|(i, mut meta)| {
            meta.segment.id = i as i32;
            meta.segment
        })
        .collect();

    info!(
        "Merged {} chunks: {} segments -> {} segments ({} duplicates removed)",
        chunks_merged,
        total_segments_before,
        final_segments.len(),
        duplicates_removed
    );

    MergeResult {
        result: TranscriptionResult {
            language,
            segments: final_segments,
        },
        total_segments_before,
        duplicates_removed,
        chunks_merged,
    }
}

/// Segment with additional metadata for merging
#[derive(Debug, Clone)]
struct SegmentWithMeta {
    segment: Segment,
    #[allow(dead_code)] // May be used for debugging or future enhancements
    chunk_index: usize,
    _original_start_ms: i64,
}

/// Determine the most common language from chunk results
fn determine_language(results: &[(TranscriptionResult, i64)]) -> String {
    let mut language_counts: HashMap<&str, usize> = HashMap::new();

    for (result, _) in results {
        *language_counts.entry(&result.language).or_insert(0) += 1;
    }

    language_counts
        .into_iter()
        .max_by_key(|(_, count)| *count)
        .map(|(lang, _)| lang.to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

/// Deduplicate overlapping segments
fn deduplicate_segments(
    segments: Vec<SegmentWithMeta>,
    config: &MergeConfig,
) -> Vec<SegmentWithMeta> {
    if segments.is_empty() {
        return segments;
    }

    let mut result: Vec<SegmentWithMeta> = Vec::with_capacity(segments.len());

    for current in segments {
        // First, check if we should replace an existing segment with higher confidence
        // This must come before duplicate detection to allow better versions to replace worse ones
        if config.prefer_higher_confidence {
            if let Some(idx) = find_replaceable_segment(&result, &current, config) {
                debug!(
                    "Replacing segment at {}ms with higher confidence version ({:.2} -> {:.2})",
                    result[idx].segment.start_ms,
                    result[idx].segment.confidence,
                    current.segment.confidence
                );
                result[idx] = current;
                continue;
            }
        }

        // Check if this segment is a duplicate of any recent segment
        let is_duplicate = result
            .iter()
            .rev()
            .take(15)
            .any(|existing| is_duplicate_segment(&existing.segment, &current.segment, config));

        if is_duplicate {
            debug!(
                "Removing duplicate segment at {}ms: '{}'",
                current.segment.start_ms,
                truncate_text(&current.segment.text, 50)
            );
            continue;
        }

        result.push(current);
    }

    result
}

/// Check if two segments are duplicates based on time and text similarity
fn is_duplicate_segment(existing: &Segment, new: &Segment, config: &MergeConfig) -> bool {
    // Check temporal proximity
    let time_diff = (new.start_ms - existing.start_ms).abs();
    if time_diff > config.max_time_diff_ms {
        return false;
    }

    // Check if they overlap in time
    let time_overlap = existing.end_ms > new.start_ms && new.end_ms > existing.start_ms;

    // Calculate text similarity
    let similarity = text_similarity(&existing.text, &new.text);

    // Consider duplicate if:
    // 1. Time difference is small AND high text similarity, OR
    // 2. Time overlap AND moderate text similarity
    if time_diff < config.overlap_ms && similarity > config.similarity_threshold {
        return true;
    }

    if time_overlap && similarity > 0.8 {
        return true;
    }

    false
}

/// Find a segment that should be replaced with a higher confidence version
fn find_replaceable_segment(
    existing: &[SegmentWithMeta],
    new: &SegmentWithMeta,
    config: &MergeConfig,
) -> Option<usize> {
    for (idx, existing_meta) in existing.iter().enumerate().rev().take(10) {
        let time_diff = (new.segment.start_ms - existing_meta.segment.start_ms).abs();
        if time_diff > config.max_time_diff_ms {
            continue;
        }

        let similarity = text_similarity(&existing_meta.segment.text, &new.segment.text);

        // If very similar and new has higher confidence, replace
        if similarity > 0.8 && new.segment.confidence > existing_meta.segment.confidence + 0.05 {
            return Some(idx);
        }
    }

    None
}

/// Calculate text similarity using Jaccard similarity of normalized words
pub fn text_similarity(text1: &str, text2: &str) -> f64 {
    let words1 = normalize_text_to_words(text1);
    let words2 = normalize_text_to_words(text2);

    if words1.is_empty() && words2.is_empty() {
        return 1.0; // Both empty = identical
    }

    if words1.is_empty() || words2.is_empty() {
        return 0.0; // One empty, one not = different
    }

    let set1: HashSet<&str> = words1.iter().map(|s| s.as_str()).collect();
    let set2: HashSet<&str> = words2.iter().map(|s| s.as_str()).collect();

    let intersection = set1.intersection(&set2).count();
    let union = set1.union(&set2).count();

    intersection as f64 / union as f64
}

/// Normalize text to lowercase words, removing punctuation
fn normalize_text_to_words(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split_whitespace()
        .map(|w| {
            w.chars()
                .filter(|c| c.is_alphanumeric())
                .collect::<String>()
        })
        .filter(|w| !w.is_empty() && w.len() > 1)
        .collect()
}

/// Truncate text for logging
fn truncate_text(text: &str, max_len: usize) -> String {
    if text.len() <= max_len {
        text.to_string()
    } else {
        format!("{}...", &text[..max_len])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_segment(id: i32, start_ms: i64, end_ms: i64, text: &str, confidence: f32) -> Segment {
        Segment {
            id,
            start_ms,
            end_ms,
            text: text.to_string(),
            confidence,
            tokens: vec![],
        }
    }

    fn make_result(language: &str, segments: Vec<Segment>) -> TranscriptionResult {
        TranscriptionResult {
            language: language.to_string(),
            segments,
        }
    }

    #[test]
    fn test_merge_empty_results() {
        let results: Vec<(TranscriptionResult, i64)> = vec![];
        let config = MergeConfig::default();
        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.segments.len(), 0);
        assert_eq!(merged.chunks_merged, 0);
        assert_eq!(merged.duplicates_removed, 0);
    }

    #[test]
    fn test_merge_single_chunk() {
        let segment = make_segment(0, 0, 5000, "Hello world", 0.9);
        let result = make_result("en", vec![segment]);

        let results = vec![(result, 0)];
        let config = MergeConfig::default();
        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.segments.len(), 1);
        assert_eq!(merged.result.language, "en");
        assert_eq!(merged.chunks_merged, 1);
        assert_eq!(merged.duplicates_removed, 0);
    }

    #[test]
    fn test_merge_two_chunks_no_overlap() {
        let seg1 = make_segment(0, 0, 5000, "First segment", 0.9);
        let seg2 = make_segment(0, 0, 5000, "Second segment", 0.8);

        let result1 = make_result("en", vec![seg1]);
        let result2 = make_result("en", vec![seg2]);

        let results = vec![(result1, 0), (result2, 10000)];
        let config = MergeConfig::from_overlap_secs(5);
        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.segments.len(), 2);
        assert_eq!(merged.result.segments[0].start_ms, 0);
        assert_eq!(merged.result.segments[1].start_ms, 10000);
        assert_eq!(merged.duplicates_removed, 0);
    }

    #[test]
    fn test_merge_two_chunks_with_duplicate() {
        let seg1 = make_segment(0, 0, 5000, "Hello world today", 0.9);
        let seg2_dup = make_segment(0, 0, 5000, "Hello world today", 0.85);
        let seg2_new = make_segment(1, 6000, 10000, "New content", 0.9);

        let result1 = make_result("en", vec![seg1]);
        let result2 = make_result("en", vec![seg2_dup, seg2_new]);

        let results = vec![(result1, 0), (result2, 0)];
        let config = MergeConfig::from_overlap_secs(5);
        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.segments.len(), 2);
        assert_eq!(merged.duplicates_removed, 1);
    }

    #[test]
    fn test_merge_timestamps_adjusted() {
        let seg1 = make_segment(0, 1000, 3000, "First", 0.9);
        let seg2 = make_segment(0, 1000, 3000, "Second", 0.9);

        let result1 = make_result("en", vec![seg1]);
        let result2 = make_result("en", vec![seg2]);

        let results = vec![(result1, 0), (result2, 300000)];
        let config = MergeConfig::from_overlap_secs(5);
        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.segments.len(), 2);
        assert_eq!(merged.result.segments[0].start_ms, 1000);
        assert_eq!(merged.result.segments[0].end_ms, 3000);
        assert_eq!(merged.result.segments[1].start_ms, 301000);
        assert_eq!(merged.result.segments[1].end_ms, 303000);
    }

    #[test]
    fn test_merge_language_detection() {
        let seg = make_segment(0, 0, 1000, "Test", 0.9);

        let result_en = make_result("en", vec![seg.clone()]);
        let result_ru1 = make_result("ru", vec![seg.clone()]);
        let result_ru2 = make_result("ru", vec![seg.clone()]);

        let results = vec![(result_en, 0), (result_ru1, 10000), (result_ru2, 20000)];
        let config = MergeConfig::default();
        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.language, "ru");
    }

    #[test]
    fn test_merge_sequential_ids() {
        let seg1 = make_segment(5, 0, 1000, "First", 0.9);
        let seg2 = make_segment(10, 2000, 3000, "Second", 0.9);
        let seg3 = make_segment(15, 0, 1000, "Third", 0.9);

        let result1 = make_result("en", vec![seg1, seg2]);
        let result2 = make_result("en", vec![seg3]);

        let results = vec![(result1, 0), (result2, 50000)];
        let config = MergeConfig::from_overlap_secs(5);
        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.segments[0].id, 0);
        assert_eq!(merged.result.segments[1].id, 1);
        assert_eq!(merged.result.segments[2].id, 2);
    }

    #[test]
    fn test_text_similarity_identical() {
        assert!((text_similarity("hello world", "hello world") - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_text_similarity_case_insensitive() {
        assert!((text_similarity("Hello World", "hello world") - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_text_similarity_with_punctuation() {
        assert!((text_similarity("Hello, world!", "hello world") - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_text_similarity_different() {
        let similarity = text_similarity("hello world", "goodbye moon");
        assert!(similarity < 0.3);
    }

    #[test]
    fn test_text_similarity_partial() {
        let similarity = text_similarity("hello world today", "hello world tomorrow");
        assert!(similarity > 0.4 && similarity < 0.6);
    }

    #[test]
    fn test_text_similarity_empty() {
        assert!((text_similarity("", "") - 1.0).abs() < 0.001);
        assert!(text_similarity("hello", "").abs() < 0.001);
        assert!(text_similarity("", "world").abs() < 0.001);
    }

    #[test]
    fn test_normalize_text_to_words() {
        let words = normalize_text_to_words("Hello, World! This is a TEST.");
        assert_eq!(words, vec!["hello", "world", "this", "is", "test"]);
    }

    #[test]
    fn test_is_duplicate_similar_time_similar_text() {
        let seg1 = make_segment(0, 1000, 3000, "Hello world", 0.9);
        let seg2 = make_segment(0, 1500, 3500, "Hello world", 0.85);
        let config = MergeConfig::default();

        assert!(is_duplicate_segment(&seg1, &seg2, &config));
    }

    #[test]
    fn test_is_duplicate_far_apart() {
        let seg1 = make_segment(0, 1000, 3000, "Hello world", 0.9);
        let seg2 = make_segment(0, 50000, 52000, "Hello world", 0.85);
        let config = MergeConfig::default();

        assert!(!is_duplicate_segment(&seg1, &seg2, &config));
    }

    #[test]
    fn test_is_duplicate_different_text() {
        let seg1 = make_segment(0, 1000, 3000, "Hello world", 0.9);
        let seg2 = make_segment(0, 1500, 3500, "Goodbye moon", 0.85);
        let config = MergeConfig::default();

        assert!(!is_duplicate_segment(&seg1, &seg2, &config));
    }

    #[test]
    fn test_prefer_higher_confidence() {
        let seg1 = make_segment(0, 0, 5000, "Hello world test", 0.7);
        let seg2 = make_segment(0, 0, 5000, "Hello world test", 0.95);

        let result1 = make_result("en", vec![seg1]);
        let result2 = make_result("en", vec![seg2]);

        let results = vec![(result1, 0), (result2, 0)];
        let mut config = MergeConfig::from_overlap_secs(5);
        config.prefer_higher_confidence = true;

        let merged = merge_transcription_results(results, config);

        assert_eq!(merged.result.segments.len(), 1);
        assert!(merged.result.segments[0].confidence > 0.9);
    }
}
