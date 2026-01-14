use rustler::{Atom, Encoder, Env, Error, Term};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

rustler::init!("Elixir.Langler.Content.ClassifierNif");

/// Training data structure
#[derive(Debug, Clone)]
struct TrainingData {
    documents: Vec<Document>,
    vocabulary: HashSet<String>,
}

#[derive(Debug, Clone)]
struct Document {
    content: String,
    topics: Vec<String>,
}

/// Trained model structure
#[derive(Debug, Clone, Serialize, Deserialize)]
struct NaiveBayesModel {
    // Prior probabilities: P(topic)
    topic_priors: HashMap<String, f64>,
    // Conditional probabilities: P(word | topic)
    word_given_topic: HashMap<String, HashMap<String, f64>>,
    // Vocabulary size for smoothing
    vocabulary_size: usize,
    // Total word count per topic
    topic_word_counts: HashMap<String, usize>,
}

/// Tokenize text into words (simple whitespace/punctuation split)
fn tokenize(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric() && c != 'ñ' && c != 'á' && c != 'é' && c != 'í' && c != 'ó' && c != 'ú' && c != 'ü')
        .filter(|s| !s.is_empty() && s.len() > 2) // Filter out very short words
        .map(|s| s.to_string())
        .collect()
}

/// Train Naive Bayes classifier
fn train_naive_bayes(training_data: &TrainingData) -> NaiveBayesModel {
    let mut topic_priors = HashMap::new();
    let mut word_given_topic: HashMap<String, HashMap<String, usize>> = HashMap::new();
    let mut topic_word_counts = HashMap::new();
    
    let total_docs = training_data.documents.len() as f64;
    
    // Count documents per topic and words per topic
    for doc in &training_data.documents {
        let tokens = tokenize(&doc.content);
        
        for topic in &doc.topics {
            // Update topic prior (count documents with this topic)
            *topic_priors.entry(topic.clone()).or_insert(0.0) += 1.0;
            
            // Count words for this topic
            let word_counts = word_given_topic.entry(topic.clone()).or_insert_with(HashMap::new);
            let topic_count = topic_word_counts.entry(topic.clone()).or_insert(0);
            
            for token in &tokens {
                if training_data.vocabulary.contains(token) {
                    *word_counts.entry(token.clone()).or_insert(0) += 1;
                    *topic_count += 1;
                }
            }
        }
    }
    
    // Normalize priors
    let topic_priors_normalized: HashMap<String, f64> = topic_priors
        .iter()
        .map(|(topic, count)| (topic.clone(), count / total_docs))
        .collect();
    
    // Convert word counts to probabilities with Laplace smoothing
    let vocabulary_size = training_data.vocabulary.len();
    let word_given_topic_probs: HashMap<String, HashMap<String, f64>> = word_given_topic
        .iter()
        .map(|(topic, word_counts)| {
            let total_words = topic_word_counts.get(topic).copied().unwrap_or(0) as f64;
            let probs: HashMap<String, f64> = word_counts
                .iter()
                .map(|(word, count)| {
                    // Laplace smoothing: (count + 1) / (total_words + vocabulary_size)
                    let prob = (count + 1) as f64 / (total_words + vocabulary_size as f64);
                    (word.clone(), prob)
                })
                .collect();
            (topic.clone(), probs)
        })
        .collect();
    
    NaiveBayesModel {
        topic_priors: topic_priors_normalized,
        word_given_topic: word_given_topic_probs,
        vocabulary_size,
        topic_word_counts,
    }
}

/// Classify a document using Naive Bayes
fn classify_naive_bayes(model: &NaiveBayesModel, document: &str) -> Vec<(String, f64)> {
    let tokens = tokenize(document);
    
    // Calculate log probabilities for each topic
    let mut topic_scores: Vec<(String, f64)> = model.topic_priors
        .iter()
        .map(|(topic, prior)| {
            // Start with log of prior probability
            let mut log_prob = prior.ln();
            
            // Add log probabilities for each word
            for token in &tokens {
                if let Some(word_probs) = model.word_given_topic.get(topic) {
                    if let Some(prob) = word_probs.get(token) {
                        log_prob += prob.ln();
                    } else {
                        // Word not seen in training for this topic - use smoothing
                        let total_words = model.topic_word_counts.get(topic).copied().unwrap_or(0) as f64;
                        let smoothed_prob = 1.0 / (total_words + model.vocabulary_size as f64);
                        log_prob += smoothed_prob.ln();
                    }
                }
            }
            
            (topic.clone(), log_prob)
        })
        .collect();
    
    // Convert log probabilities to probabilities and normalize
    let max_log_prob = topic_scores.iter().map(|(_, prob)| *prob).fold(f64::NEG_INFINITY, f64::max);
    topic_scores = topic_scores
        .into_iter()
        .map(|(topic, log_prob)| {
            let prob = (log_prob - max_log_prob).exp();
            (topic, prob)
        })
        .collect();
    
    // Normalize to sum to 1
    let sum: f64 = topic_scores.iter().map(|(_, prob)| prob).sum();
    if sum > 0.0 {
        topic_scores = topic_scores
            .into_iter()
            .map(|(topic, prob)| (topic, prob / sum))
            .collect();
    }
    
    // Sort by probability descending
    topic_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    
    topic_scores
}

#[rustler::nif(schedule = "DirtyCpu")]
fn train<'a>(env: Env<'a>, training_data_term: Term<'a>) -> Result<Term<'a>, Error> {
    // Parse training data from Elixir
    // Expected format: list of maps %{"content" => "...", "topics" => ["topic1", ...]}
    let docs_list: Vec<Term> = training_data_term.decode()?;
    
    let mut documents = Vec::new();
    let mut vocabulary = HashSet::new();
    
    let content_atom = Atom::from_str(env, "content")?;
    let topics_atom = Atom::from_str(env, "topics")?;
    
    for doc_term in docs_list {
        // Decode as map with atom keys (rustler uses atoms)
        let content: Option<String> = match doc_term.map_get(content_atom) {
            Ok(term) => term.decode().ok(),
            Err(_) => None,
        };
        
        let topics: Option<Vec<String>> = match doc_term.map_get(topics_atom) {
            Ok(term) => term.decode().ok(),
            Err(_) => None,
        };
        
        let (content, topics) = match (content, topics) {
            (Some(c), Some(t)) if !c.is_empty() && !t.is_empty() => (c, t),
            _ => continue,
        };
        
        // Build vocabulary from document
        let tokens = tokenize(&content);
        for token in tokens {
            vocabulary.insert(token);
        }
        
        documents.push(Document { content, topics });
    }
    
    if documents.is_empty() {
        return Err(Error::Term(Box::new("No valid training documents".to_string())));
    }
    
    let training_data = TrainingData { documents, vocabulary };
    let model = train_naive_bayes(&training_data);
    
    // Serialize model to JSON
    let model_json = serde_json::to_string(&model)
        .map_err(|e| Error::Term(Box::new(format!("Failed to serialize model: {}", e))))?;
    
    // Return JSON string
    Ok(model_json.encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn classify<'a>(env: Env<'a>, document: String, model_json: String) -> Result<Term<'a>, Error> {
    // Deserialize model from JSON
    let model: NaiveBayesModel = serde_json::from_str(&model_json)
        .map_err(|e| Error::Term(Box::new(format!("Failed to deserialize model: {}", e))))?;
    
    // Classify document
    let topic_scores = classify_naive_bayes(&model, &document);
    
    // Build result map with topics list
    let mut topics_list = Vec::new();
    for (topic, confidence) in topic_scores {
        let mut topic_map = rustler::types::map::map_new(env);
        topic_map = topic_map.map_put(
            Atom::from_str(env, "topic")?.encode(env),
            topic.encode(env)
        ).map_err(|_| Error::BadArg)?;
        topic_map = topic_map.map_put(
            Atom::from_str(env, "confidence")?.encode(env),
            confidence.encode(env)
        ).map_err(|_| Error::BadArg)?;
        topics_list.push(topic_map.encode(env));
    }
    
    let mut result = rustler::types::map::map_new(env);
    result = result.map_put(
        Atom::from_str(env, "topics")?.encode(env),
        topics_list.encode(env)
    ).map_err(|_| Error::BadArg)?;
    
    Ok(result.encode(env))
}
