use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use log::info;
use std::path::PathBuf;

#[cfg(feature = "whisper")]
use orangenote_cli::AudioDecoder;

/// OrangeNote CLI - Offline audio transcription tool
#[derive(Parser, Debug)]
#[command(name = "orangenote-cli")]
#[command(about = "Transcribe audio files using whisper.cpp in offline mode", long_about = None)]
#[command(version = env!("CARGO_PKG_VERSION"))]
#[command(author = "OrangeNote Team")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Enable verbose logging
    #[arg(short, long, global = true)]
    verbose: bool,

    /// Log level (trace, debug, info, warn, error)
    #[arg(short = 'L', long, global = true, value_name = "LEVEL")]
    log_level: Option<String>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Transcribe an audio file
    Transcribe {
        /// Path to audio file (mp3, wav, m4a, flac, etc.)
        #[arg(value_name = "INPUT")]
        input: PathBuf,

        /// Whisper model to use (tiny, base, small, medium, large)
        #[arg(short, long, default_value = "base")]
        model: String,

        /// Language code (e.g., 'en', 'ru', 'fr'). Auto-detect if not specified
        #[arg(short, long)]
        language: Option<String>,

        /// Output format (json, txt, srt, vtt, tsv)
        #[arg(short, long, default_value = "json")]
        format: String,

        /// Output file path. If not specified, output goes to stdout
        #[arg(short, long)]
        output: Option<PathBuf>,

        /// Number of threads for processing
        #[arg(short, long, default_value = "4")]
        threads: usize,

        /// Translate to English
        #[arg(long)]
        translate: bool,

        /// Chunk size in minutes for long audio files (0 = no chunking)
        /// Recommended: 5-10 minutes for optimal transcription quality
        #[arg(long, default_value = "0", value_name = "MINUTES")]
        chunk_size: u32,

        /// Overlap between chunks in seconds (helps maintain context at boundaries)
        #[arg(long, default_value = "5", value_name = "SECONDS")]
        chunk_overlap: u32,
    },

    /// Manage transcription models
    #[command(subcommand)]
    Model(ModelCommands),

    /// Show system information
    Info,
}

#[derive(Subcommand, Debug)]
enum ModelCommands {
    /// List available models
    List,

    /// Download a model
    Download {
        /// Model name (tiny, base, small, medium, large)
        #[arg(value_name = "MODEL")]
        model: String,

        /// Force re-download if model already exists
        #[arg(short, long)]
        force: bool,
    },

    /// Remove a downloaded model
    Remove {
        /// Model name to remove
        #[arg(value_name = "MODEL")]
        model: String,
    },

    /// Check model status
    Status,
}

fn init_logging(verbose: bool, log_level: Option<String>) {
    let level = if let Some(level) = log_level {
        level.to_uppercase()
    } else if verbose {
        "DEBUG".to_string()
    } else {
        "INFO".to_string()
    };

    env_logger::Builder::from_default_env()
        .filter_level(level.parse().unwrap_or(log::LevelFilter::Info))
        .format_timestamp_millis()
        .init();
}

#[cfg(feature = "whisper")]
fn validate_input_file(path: &PathBuf) -> Result<()> {
    if !path.exists() {
        anyhow::bail!("Input file does not exist: {}", path.display());
    }

    if !path.is_file() {
        anyhow::bail!("Path is not a file: {}", path.display());
    }

    let extension = path
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|s| s.to_lowercase());

    let supported_formats = vec!["mp3", "wav", "m4a", "flac", "ogg", "wma"];
    if let Some(ext) = extension {
        if !supported_formats.contains(&ext.as_str()) {
            anyhow::bail!(
                "Unsupported audio format: .{}. Supported formats: {}",
                ext,
                supported_formats.join(", ")
            );
        }
    } else {
        anyhow::bail!("Input file has no extension");
    }

    Ok(())
}

fn validate_model(model: &str) -> Result<()> {
    let valid_models = vec!["tiny", "base", "small", "medium", "large"];
    if !valid_models.contains(&model) {
        anyhow::bail!(
            "Invalid model: '{}'. Valid models: {}",
            model,
            valid_models.join(", ")
        );
    }
    Ok(())
}

/// Validate chunk configuration parameters
#[cfg(feature = "whisper")]
fn validate_chunk_config(chunk_size: u32, chunk_overlap: u32) -> Result<()> {
    // chunk_size = 0 means no chunking, which is valid
    if chunk_size == 0 {
        return Ok(());
    }

    // Minimum chunk size is 1 minute
    if chunk_size < 1 {
        anyhow::bail!(
            "Chunk size must be at least 1 minute (got {} minutes). Use 0 to disable chunking.",
            chunk_size
        );
    }

    // Convert chunk_size to seconds for comparison
    let chunk_size_secs = chunk_size * 60;

    // Overlap must be less than chunk size
    if chunk_overlap >= chunk_size_secs {
        anyhow::bail!(
            "Chunk overlap ({} seconds) must be less than chunk size ({} seconds = {} minutes)",
            chunk_overlap,
            chunk_size_secs,
            chunk_size
        );
    }

    // Warn if overlap is more than 50% of chunk size
    if chunk_overlap > chunk_size_secs / 2 {
        log::warn!(
            "Large overlap ({} seconds) may cause excessive processing. \
             Consider using overlap <= {} seconds (50% of chunk size).",
            chunk_overlap,
            chunk_size_secs / 2
        );
    }

    Ok(())
}

#[cfg(feature = "whisper")]
fn validate_format(format: &str) -> Result<()> {
    let valid_formats = vec!["json", "txt", "srt", "vtt", "tsv"];
    if !valid_formats.contains(&format) {
        anyhow::bail!(
            "Invalid format: '{}'. Valid formats: {}",
            format,
            valid_formats.join(", ")
        );
    }
    Ok(())
}

#[cfg(feature = "whisper")]
/// Format transcription result as JSON
fn format_json(result: &orangenote_cli::TranscriptionResult) -> Result<String> {
    serde_json::to_string_pretty(&serde_json::json!({
        "language": result.language,
        "segments": result.segments.iter().map(|seg| {
            serde_json::json!({
                "id": seg.id,
                "start": seg.start_time_formatted(),
                "end": seg.end_time_formatted(),
                "start_ms": seg.start_ms,
                "end_ms": seg.end_ms,
                "text": seg.text,
                "confidence": seg.confidence,
            })
        }).collect::<Vec<_>>()
    }))
    .context("Failed to serialize JSON")
}

#[cfg(feature = "whisper")]
/// Format transcription result as plain text
fn format_txt(result: &orangenote_cli::TranscriptionResult) -> String {
    result
        .segments
        .iter()
        .map(|seg| format!("[{}] {}", seg.start_time_formatted(), seg.text))
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(feature = "whisper")]
/// Format transcription result as SRT (SubRip)
fn format_srt(result: &orangenote_cli::TranscriptionResult) -> String {
    result
        .segments
        .iter()
        .map(|seg| {
            format!(
                "{}\n{} --> {}\n{}\n",
                seg.id + 1,
                format_srt_time(seg.start_ms),
                format_srt_time(seg.end_ms),
                seg.text
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(feature = "whisper")]
/// Format transcription result as VTT (WebVTT)
fn format_vtt(result: &orangenote_cli::TranscriptionResult) -> String {
    let mut output = "WEBVTT\n\n".to_string();
    output.push_str(
        &result
            .segments
            .iter()
            .map(|seg| {
                format!(
                    "{} --> {}\n{}\n",
                    format_srt_time(seg.start_ms),
                    format_srt_time(seg.end_ms),
                    seg.text
                )
            })
            .collect::<Vec<_>>()
            .join("\n"),
    );
    output
}

#[cfg(feature = "whisper")]
/// Format transcription result as TSV (tab-separated values)
fn format_tsv(result: &orangenote_cli::TranscriptionResult) -> String {
    let header = "ID\tStart\tEnd\tStartMS\tEndMS\tConfidence\tText\n";
    let rows = result
        .segments
        .iter()
        .map(|seg| {
            format!(
                "{}\t{}\t{}\t{}\t{}\t{:.3}\t{}",
                seg.id,
                seg.start_time_formatted(),
                seg.end_time_formatted(),
                seg.start_ms,
                seg.end_ms,
                seg.confidence,
                seg.text
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    format!("{}{}\n", header, rows)
}

#[cfg(feature = "whisper")]
/// Format time for SRT/VTT format (HH:MM:SS,mmm)
fn format_srt_time(ms: i64) -> String {
    let total_seconds = ms / 1000;
    let milliseconds = ms % 1000;
    let seconds = total_seconds % 60;
    let minutes = (total_seconds / 60) % 60;
    let hours = total_seconds / 3600;

    format!(
        "{:02}:{:02}:{:02},{:03}",
        hours, minutes, seconds, milliseconds
    )
}

#[cfg(feature = "whisper")]
#[allow(clippy::too_many_arguments)]
async fn handle_transcribe(
    input: PathBuf,
    model: String,
    language: Option<String>,
    format: String,
    output: Option<PathBuf>,
    threads: usize,
    translate: bool,
    chunk_size: u32,
    chunk_overlap: u32,
) -> Result<()> {
    validate_input_file(&input).context("Input file validation failed")?;
    validate_model(&model).context("Model validation failed")?;
    validate_format(&format).context("Output format validation failed")?;
    validate_chunk_config(chunk_size, chunk_overlap).context("Chunk config validation failed")?;

    info!("Starting transcription...");
    info!("Input file: {}", input.display());
    info!("Model: {}", model);
    if let Some(lang) = &language {
        info!("Language: {}", lang);
    } else {
        info!("Language: auto-detect");
    }
    info!("Output format: {}", format);
    info!("Threads: {}", threads);
    info!("Translate: {}", translate);

    if chunk_size > 0 {
        info!(
            "Chunking: {} minute chunks with {} second overlap",
            chunk_size, chunk_overlap
        );
    } else {
        info!("Chunking: disabled");
    }

    // Step A2: Extract audio metadata using AudioDecoder
    let decoder = AudioDecoder::new(&input).context("Failed to create audio decoder")?;
    let metadata = decoder
        .get_metadata()
        .context("Failed to extract audio metadata")?;

    // Display audio information
    println!("\n📄 Audio File Information:");
    println!("  File: {}", input.display());
    println!("  Format: {}", metadata.format.as_str());
    println!("  Size: {}", metadata.file_size_human());
    println!("  {}", metadata.format_info());

    #[cfg(feature = "whisper")]
    {
        use orangenote_cli::{ModelSize, WhisperModelManager};

        // Initialize model manager
        let model_manager =
            WhisperModelManager::new().context("Failed to initialize model manager")?;

        println!("\n🤖 Initializing transcriber...");

        // Parse model name to ModelSize enum
        let model_size =
            ModelSize::from_str(&model).context(format!("Invalid model name: {}", model))?;

        // Create transcriber (will download model if needed)
        let transcriber = orangenote_cli::WhisperTranscriber::from_model_manager(
            &model_manager,
            model_size,
            threads,
        )
        .await
        .context("Failed to initialize transcriber")?;

        println!("✓ Transcriber ready (model: {})", model);

        println!("\n🎵 Processing audio...");

        // Transcribe - with or without chunking
        let result = if chunk_size > 0 {
            use orangenote_cli::ChunkConfig;

            let config = ChunkConfig {
                chunk_duration_secs: chunk_size * 60,
                overlap_secs: chunk_overlap,
            };

            println!(
                "  📦 Using chunked transcription ({} min chunks, {}s overlap)",
                chunk_size, chunk_overlap
            );

            transcriber
                .transcribe_file_chunked(
                    &input,
                    language.as_deref(),
                    translate,
                    &config,
                    |current, total| {
                        println!("  Processing chunk {}/{}...", current + 1, total);
                    },
                )
                .context("Chunked transcription failed")?
        } else {
            transcriber
                .transcribe_file(&input, language.as_deref(), translate)
                .context("Transcription failed")?
        };

        println!("✓ Transcription complete!");
        println!("  Detected language: {}", result.language);
        println!("  Segments: {}", result.segments.len());
        println!(
            "  Average confidence: {:.2}%",
            result.average_confidence() * 100.0
        );

        println!("\n📝 Transcription Results:\n");

        // Format the output
        let formatted_output = match format.as_str() {
            "json" => format_json(&result).context("Failed to format JSON")?,
            "txt" => format_txt(&result),
            "srt" => format_srt(&result),
            "vtt" => format_vtt(&result),
            "tsv" => format_tsv(&result),
            _ => unreachable!(),
        };

        // Write output
        if let Some(output_path) = output {
            std::fs::write(&output_path, &formatted_output)
                .context("Failed to write output file")?;
            println!("✓ Output written to: {}", output_path.display());
        } else {
            println!("{}", formatted_output);
        }

        println!("\n✓ Transcription complete!\n");
    }

    #[cfg(not(feature = "whisper"))]
    {
        println!("\n❌ Error: Whisper feature not enabled!");
        println!("Please rebuild with: cargo build --features whisper");
        anyhow::bail!("Whisper feature not enabled");
    }

    Ok(())
}

#[cfg(not(feature = "whisper"))]
async fn handle_transcribe(
    _input: PathBuf,
    _model: String,
    _language: Option<String>,
    _format: String,
    _output: Option<PathBuf>,
    _threads: usize,
    _translate: bool,
    _chunk_size: u32,
    _chunk_overlap: u32,
) -> Result<()> {
    anyhow::bail!("Whisper feature not enabled. Rebuild with: cargo build --features whisper")
}

async fn handle_model_list() -> Result<()> {
    info!("Listing available models...");
    println!("Available Whisper models:");
    println!("  • tiny   (39M)   - Fastest, low accuracy");
    println!("  • base   (140M)  - Default, good balance");
    println!("  • small  (466M)  - Better accuracy");
    println!("  • medium (1.5G)  - High accuracy");
    println!("  • large  (2.9G)  - Highest accuracy");

    #[cfg(feature = "whisper")]
    {
        use orangenote_cli::WhisperModelManager;

        let model_manager =
            WhisperModelManager::new().context("Failed to initialize model manager")?;

        println!("\n📦 Downloaded Models:");
        let cached = model_manager
            .list_cached_models()
            .context("Failed to list cached models")?;

        if cached.is_empty() {
            println!("  (none)");
        } else {
            for model in cached {
                let path = model_manager.get_model_path(model);
                if let Ok(metadata) = std::fs::metadata(&path) {
                    let size_mb = metadata.len() / 1_000_000;
                    println!("  ✓ {} ({}MB)", model.display_name(), size_mb);
                } else {
                    println!("  ✓ {}", model.display_name());
                }
            }
        }
    }

    Ok(())
}

async fn handle_model_download(model: String, _force: bool) -> Result<()> {
    validate_model(&model).context("Model validation failed")?;

    #[cfg(feature = "whisper")]
    {
        use orangenote_cli::{ModelSize, WhisperModelManager};

        info!("Downloading model: {}", model);

        let model_manager =
            WhisperModelManager::new().context("Failed to initialize model manager")?;

        // Parse model name
        let model_size =
            ModelSize::from_str(&model).context(format!("Invalid model name: {}", model))?;

        println!("📥 Downloading model: {}", model);

        // Check if already cached and not forcing re-download
        if model_manager.is_cached(model_size) && !_force {
            println!("✓ Model {} already cached", model);
        } else {
            model_manager
                .download_model(model_size)
                .await
                .context("Failed to download model")?;
            println!("✓ Model downloaded successfully!");
        }
    }

    #[cfg(not(feature = "whisper"))]
    {
        let _ = _force; // Suppress unused warning
        return Err(anyhow::anyhow!("Whisper feature not enabled"));
    }

    #[cfg(feature = "whisper")]
    Ok(())
}

#[cfg(feature = "whisper")]
async fn handle_model_remove(model: String) -> Result<()> {
    validate_model(&model).context("Model validation failed")?;

    use orangenote_cli::{ModelSize, WhisperModelManager};

    info!("Removing model: {}", model);

    let model_manager = WhisperModelManager::new().context("Failed to initialize model manager")?;

    // Parse model name
    let model_size =
        ModelSize::from_str(&model).context(format!("Invalid model name: {}", model))?;

    model_manager
        .remove_model(model_size)
        .context("Failed to remove model")?;

    println!("✓ Model '{}' removed successfully!", model);

    Ok(())
}

#[cfg(not(feature = "whisper"))]
async fn handle_model_remove(model: String) -> Result<()> {
    let _ = model;
    anyhow::bail!("Whisper feature not enabled");
}

#[cfg(feature = "whisper")]
async fn handle_model_status() -> Result<()> {
    info!("Checking model status...");

    use orangenote_cli::WhisperModelManager;

    let model_manager = WhisperModelManager::new().context("Failed to initialize model manager")?;

    let cached = model_manager
        .list_cached_models()
        .context("Failed to list cached models")?;

    println!("📊 Model Cache Status:");
    println!("  Cache directory: {}", model_manager.cache_dir().display());
    println!("  Downloaded models: {}", cached.len());

    if !cached.is_empty() {
        let total_size = model_manager.get_cache_size().unwrap_or(0);
        println!("  Total size: {:.2} MB", total_size as f64);
    }

    Ok(())
}

#[cfg(not(feature = "whisper"))]
async fn handle_model_status() -> Result<()> {
    anyhow::bail!("Whisper feature not enabled");
}

async fn handle_info() -> Result<()> {
    info!("Displaying system information...");
    println!("OrangeNote CLI v{}", env!("CARGO_PKG_VERSION"));
    println!("System Information:");
    println!("  • OS: {}", std::env::consts::OS);
    println!("  • Arch: {}", std::env::consts::ARCH);
    println!("  • Family: {}", std::env::consts::FAMILY);

    #[cfg(feature = "whisper")]
    println!("  • Whisper support: ✓ Enabled");

    #[cfg(not(feature = "whisper"))]
    println!("  • Whisper support: ✗ Disabled (rebuild with --features whisper)");

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    init_logging(cli.verbose, cli.log_level);

    info!("OrangeNote CLI started");

    match cli.command {
        Some(Commands::Transcribe {
            input,
            model,
            language,
            format,
            output,
            threads,
            translate,
            chunk_size,
            chunk_overlap,
        }) => {
            handle_transcribe(
                input,
                model,
                language,
                format,
                output,
                threads,
                translate,
                chunk_size,
                chunk_overlap,
            )
            .await?;
        }
        Some(Commands::Model(ModelCommands::List)) => {
            handle_model_list().await?;
        }
        Some(Commands::Model(ModelCommands::Download { model, force })) => {
            handle_model_download(model, force).await?;
        }
        Some(Commands::Model(ModelCommands::Remove { model })) => {
            handle_model_remove(model).await?;
        }
        Some(Commands::Model(ModelCommands::Status)) => {
            handle_model_status().await?;
        }
        Some(Commands::Info) => {
            handle_info().await?;
        }
        None => {
            println!("OrangeNote CLI v{}", env!("CARGO_PKG_VERSION"));
            println!("\nNo command specified. Use --help for usage information.");
        }
    }

    Ok(())
}
