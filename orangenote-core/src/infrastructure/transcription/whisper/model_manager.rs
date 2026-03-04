//! Whisper Model Manager
//!
//! Handles downloading, caching, and verifying whisper.cpp models.
//! Models are cached in `~/.cache/orangenote/models/` for reuse across sessions.

use anyhow::{anyhow, Context, Result};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

#[cfg(feature = "whisper")]
use futures::stream::StreamExt;

/// Available whisper model sizes
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ModelSize {
    Tiny,
    TinyEn,
    Base,
    BaseEn,
    Small,
    SmallEn,
    Medium,
    MediumEn,
    Large,
}

impl ModelSize {
    /// Get the model filename
    pub fn filename(&self) -> &'static str {
        match self {
            Self::Tiny => "ggml-tiny.bin",
            Self::TinyEn => "ggml-tiny.en.bin",
            Self::Base => "ggml-base.bin",
            Self::BaseEn => "ggml-base.en.bin",
            Self::Small => "ggml-small.bin",
            Self::SmallEn => "ggml-small.en.bin",
            Self::Medium => "ggml-medium.bin",
            Self::MediumEn => "ggml-medium.en.bin",
            Self::Large => "ggml-large.bin",
        }
    }

    /// Get the model display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Tiny => "tiny",
            Self::TinyEn => "tiny.en",
            Self::Base => "base",
            Self::BaseEn => "base.en",
            Self::Small => "small",
            Self::SmallEn => "small.en",
            Self::Medium => "medium",
            Self::MediumEn => "medium.en",
            Self::Large => "large",
        }
    }

    /// Get approximate model size in MB
    pub fn size_mb(&self) -> u32 {
        match self {
            Self::Tiny | Self::TinyEn => 39,
            Self::Base | Self::BaseEn => 140,
            Self::Small | Self::SmallEn => 466,
            Self::Medium | Self::MediumEn => 1500,
            Self::Large => 3000,
        }
    }

    /// Parse from string (e.g., "tiny", "base", "tiny.en")
    pub fn from_str(s: &str) -> Result<Self> {
        match s.to_lowercase().as_str() {
            "tiny" => Ok(Self::Tiny),
            "tiny.en" => Ok(Self::TinyEn),
            "base" => Ok(Self::Base),
            "base.en" => Ok(Self::BaseEn),
            "small" => Ok(Self::Small),
            "small.en" => Ok(Self::SmallEn),
            "medium" => Ok(Self::Medium),
            "medium.en" => Ok(Self::MediumEn),
            "large" => Ok(Self::Large),
            _ => Err(anyhow!(
                "Unknown model: {}. Available: tiny, tiny.en, base, base.en, small, small.en, medium, medium.en, large",
                s
            )),
        }
    }
}

/// Model download source
#[derive(Debug, Clone)]
pub struct ModelSource {
    /// Base URL for model downloads
    pub base_url: String,
    /// Name of the source for display
    pub name: &'static str,
}

impl ModelSource {
    /// HuggingFace model source (primary)
    pub fn huggingface() -> Self {
        Self {
            base_url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main".to_string(),
            name: "HuggingFace",
        }
    }

    /// Construct full download URL for a model
    pub fn download_url(&self, model: ModelSize) -> String {
        format!("{}/{}", self.base_url, model.filename())
    }
}

/// Manages whisper model caching and downloading
pub struct WhisperModelManager {
    cache_dir: PathBuf,
    source: ModelSource,
}

impl WhisperModelManager {
    /// Create a new model manager with default cache directory
    pub fn new() -> Result<Self> {
        let cache_dir = Self::default_cache_dir()?;
        Ok(Self {
            cache_dir,
            source: ModelSource::huggingface(),
        })
    }

    /// Create with a custom cache directory
    pub fn with_cache_dir(cache_dir: PathBuf) -> Self {
        Self {
            cache_dir,
            source: ModelSource::huggingface(),
        }
    }

    /// Create with custom cache directory and source
    pub fn with_cache_and_source(cache_dir: PathBuf, source: ModelSource) -> Self {
        Self { cache_dir, source }
    }

    /// Get the default cache directory (~/.cache/orangenote/models)
    pub fn default_cache_dir() -> Result<PathBuf> {
        let cache_root = if let Ok(xdg_cache) = std::env::var("XDG_CACHE_HOME") {
            PathBuf::from(xdg_cache)
        } else if let Ok(home) = std::env::var("HOME") {
            PathBuf::from(home).join(".cache")
        } else if let Ok(home) = std::env::var("USERPROFILE") {
            // Windows
            PathBuf::from(home)
                .join("AppData")
                .join("Local")
                .join("cache")
        } else {
            return Err(anyhow!("Cannot determine home directory"));
        };

        Ok(cache_root.join("orangenote").join("models"))
    }

    /// Get path to a cached model
    pub fn get_model_path(&self, model: ModelSize) -> PathBuf {
        self.cache_dir.join(model.filename())
    }

    /// Check if a model is cached locally
    pub fn is_cached(&self, model: ModelSize) -> bool {
        self.get_model_path(model).exists()
    }

    /// Get or download a model
    ///
    /// Returns the path to the model file. If the model is already cached,
    /// returns the path immediately. Otherwise, downloads it first.
    pub async fn get_or_download(&self, model: ModelSize) -> Result<PathBuf> {
        let model_path = self.get_model_path(model);

        // Return cached model if it exists and is valid
        if model_path.exists() {
            // Optionally verify checksum (optional)
            return Ok(model_path);
        }

        // Download the model
        self.download_model(model).await?;

        Ok(model_path)
    }

    /// Download a model from the configured source (async version)
    #[cfg(feature = "whisper")]
    pub async fn download_model(&self, model: ModelSize) -> Result<()> {
        // Ensure cache directory exists
        fs::create_dir_all(&self.cache_dir).context("Failed to create model cache directory")?;

        let model_path = self.get_model_path(model);
        let url = self.source.download_url(model);

        println!(
            "Downloading {} model ({} MB) from {}...",
            model.display_name(),
            model.size_mb(),
            self.source.name
        );

        self.download_model_impl(&url, &model_path, model).await
    }

    /// Download a model implementation (async)
    #[cfg(feature = "whisper")]
    async fn download_model_impl(
        &self,
        url: &str,
        destination: &Path,
        model: ModelSize,
    ) -> Result<()> {
        use indicatif::{ProgressBar, ProgressStyle};

        // Create HTTP client
        let client = reqwest::Client::new();

        // Send GET request
        let response = client
            .get(url)
            .send()
            .await
            .context(format!("Failed to download model from {}", url))?;

        // Get total size
        let total_size = response.content_length().unwrap_or(0);

        // Create progress bar
        let pb = ProgressBar::new(total_size);
        pb.set_style(
            ProgressStyle::default_bar()
                .template("{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({eta})")
                .context("Failed to set progress bar style")?
                .progress_chars("#>-"),
        );

        // Download with progress
        let mut file = fs::File::create(destination).context(format!(
            "Failed to create model file at {}",
            destination.display()
        ))?;

        let mut stream = response.bytes_stream();
        let mut downloaded = 0u64;

        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result.context("Failed to read chunk from response")?;
            file.write_all(&chunk)
                .context("Failed to write chunk to file")?;

            downloaded += chunk.len() as u64;
            pb.set_position(downloaded);
        }

        pb.finish_with_message(format!(
            "✓ Downloaded {} model to {}",
            model.display_name(),
            destination.display()
        ));

        Ok(())
    }

    /// Download a model (stub when feature is not enabled)
    #[cfg(not(feature = "whisper"))]
    pub fn download_model(&self, _model: ModelSize) -> Result<()> {
        Err(anyhow!(
            "Whisper support not enabled. \
            Compile with --features whisper to enable model downloading"
        ))
    }

    /// List all available models
    pub fn list_available_models() -> Vec<(ModelSize, u32)> {
        vec![
            (ModelSize::Tiny, ModelSize::Tiny.size_mb()),
            (ModelSize::TinyEn, ModelSize::TinyEn.size_mb()),
            (ModelSize::Base, ModelSize::Base.size_mb()),
            (ModelSize::BaseEn, ModelSize::BaseEn.size_mb()),
            (ModelSize::Small, ModelSize::Small.size_mb()),
            (ModelSize::SmallEn, ModelSize::SmallEn.size_mb()),
            (ModelSize::Medium, ModelSize::Medium.size_mb()),
            (ModelSize::MediumEn, ModelSize::MediumEn.size_mb()),
            (ModelSize::Large, ModelSize::Large.size_mb()),
        ]
    }

    /// List cached models
    pub fn list_cached_models(&self) -> Result<Vec<ModelSize>> {
        let mut cached = Vec::new();

        for (model, _) in Self::list_available_models() {
            if self.is_cached(model) {
                cached.push(model);
            }
        }

        Ok(cached)
    }

    /// Get total size of cached models in MB
    pub fn get_cache_size(&self) -> Result<u64> {
        let mut total = 0u64;

        for (model, _) in Self::list_available_models() {
            if let Ok(metadata) = fs::metadata(self.get_model_path(model)) {
                total += metadata.len();
            }
        }

        Ok(total / 1024 / 1024)
    }

    /// Remove a cached model
    pub fn remove_model(&self, model: ModelSize) -> Result<()> {
        let model_path = self.get_model_path(model);

        if !model_path.exists() {
            return Err(anyhow!(
                "Model {} not found at {}",
                model.display_name(),
                model_path.display()
            ));
        }

        fs::remove_file(&model_path)
            .context(format!("Failed to remove model {}", model.display_name()))?;

        println!("✓ Removed model: {}", model.display_name());

        Ok(())
    }

    /// Clear all cached models
    pub fn clear_cache(&self) -> Result<()> {
        if !self.cache_dir.exists() {
            return Ok(());
        }

        fs::remove_dir_all(&self.cache_dir).context("Failed to clear model cache")?;

        println!("✓ Cleared model cache at {}", self.cache_dir.display());

        Ok(())
    }

    /// Get human-readable model size string
    pub fn format_size(&self, model: ModelSize) -> String {
        format!("~{} MB", model.size_mb())
    }

    /// Get the cache directory path
    pub fn cache_dir(&self) -> &Path {
        &self.cache_dir
    }
}

impl Default for WhisperModelManager {
    fn default() -> Self {
        Self::new().expect("Failed to initialize model manager")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_model_size_parsing() {
        assert_eq!(ModelSize::from_str("tiny").unwrap(), ModelSize::Tiny);
        assert_eq!(ModelSize::from_str("base").unwrap(), ModelSize::Base);
        assert_eq!(ModelSize::from_str("tiny.en").unwrap(), ModelSize::TinyEn);
        assert!(ModelSize::from_str("invalid").is_err());
    }

    #[test]
    fn test_model_filenames() {
        assert_eq!(ModelSize::Tiny.filename(), "ggml-tiny.bin");
        assert_eq!(ModelSize::Base.filename(), "ggml-base.bin");
        assert_eq!(ModelSize::Large.filename(), "ggml-large.bin");
    }

    #[test]
    fn test_model_display_names() {
        assert_eq!(ModelSize::Tiny.display_name(), "tiny");
        assert_eq!(ModelSize::TinyEn.display_name(), "tiny.en");
        assert_eq!(ModelSize::Large.display_name(), "large");
    }

    #[test]
    fn test_available_models_count() {
        let models = WhisperModelManager::list_available_models();
        assert_eq!(models.len(), 9); // tiny, tiny.en, base, base.en, small, small.en, medium, medium.en, large
    }

    #[test]
    fn test_model_sizes() {
        assert_eq!(ModelSize::Tiny.size_mb(), 39);
        assert_eq!(ModelSize::Base.size_mb(), 140);
        assert_eq!(ModelSize::Large.size_mb(), 3000);
    }

    #[test]
    fn test_huggingface_url() {
        let source = ModelSource::huggingface();
        let url = source.download_url(ModelSize::Tiny);
        assert!(url.contains("huggingface.co"));
        assert!(url.contains("ggml-tiny.bin"));
    }

    #[test]
    fn test_custom_cache_dir() {
        let cache_dir = PathBuf::from("/tmp/test_cache");
        let manager = WhisperModelManager::with_cache_dir(cache_dir.clone());
        assert_eq!(manager.cache_dir, cache_dir);
    }
}
