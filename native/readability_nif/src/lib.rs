use rustler::{Atom, Encoder, Env, Error, Term};
use scraper::{Html, Selector};

rustler::init!("Elixir.Langler.Content.ReadabilityNif");

/// Extract plain text from all <p> tags in HTML content
/// Filters out short paragraphs (< 20 chars) which are likely navigation/UI elements
/// Uses source-specific rules when available (e.g., El País article body region)
fn extract_paragraph_text(html: &str, base_url: Option<&str>) -> String {
    let document = Html::parse_document(html);
    
    // Determine if we should use source-specific extraction
    // For El País, check if URL contains elpais.com
    let is_elpais = base_url
        .map(|url| url.contains("elpais.com"))
        .unwrap_or(false);
    
    // For El País, extract only from the article body region
    if is_elpais {
        if let Ok(region_selector) = Selector::parse("[data-dtm-region=\"articulo_cuerpo\"]") {
            if let Some(article_body) = document.select(&region_selector).next() {
                // Extract paragraphs only from within the article body region
                return extract_paragraphs_from_element(&article_body);
            }
        }
    }
    
    // Fallback: extract from all paragraphs in the document
    extract_paragraphs_from_document(&document)
}

/// Extract paragraphs from a specific HTML element
/// Stops extraction when hitting known end markers
fn extract_paragraphs_from_element(element: &scraper::element_ref::ElementRef) -> String {
    let p_selector = match Selector::parse("p") {
        Ok(sel) => sel,
        Err(_) => return String::new(),
    };
    
    // Markers that indicate the end of the article content
    let end_markers = [
        "Tu suscripción",
        "Sobre la firma",
        "Sobre el autor",
        "Suscríbete",
        "Nuevo curso",
        "términos y condiciones de la suscripción",
    ];
    
    let mut paragraphs: Vec<String> = Vec::new();
    for p_element in element.select(&p_selector) {
        let text = p_element.text().collect::<Vec<_>>().join(" ");
        let trimmed = text.trim().to_string();
        
        // Check if this paragraph contains an end marker
        if let Some(marker) = end_markers.iter().find(|m| trimmed.contains(*m)) {
            // If marker found, truncate at the marker and stop
            if let Some(pos) = trimmed.find(marker) {
                let truncated = trimmed[..pos].trim().to_string();
                if truncated.len() >= 20 {
                    paragraphs.push(truncated);
                }
            }
            break; // Stop processing more paragraphs
        }
        
        // No marker found, add the paragraph if it's long enough
        if trimmed.len() >= 20 {
            paragraphs.push(trimmed);
        }
    }
    
    paragraphs.join("\n\n")
}

/// Extract paragraphs from the entire document
/// Stops extraction when hitting known end markers (subscription prompts, author bios, etc.)
fn extract_paragraphs_from_document(document: &Html) -> String {
    let p_selector = match Selector::parse("p") {
        Ok(sel) => sel,
        Err(_) => return String::new(),
    };
    
    // Markers that indicate the end of the article content
    let end_markers = [
        "Tu suscripción",
        "Sobre la firma",
        "Sobre el autor",
        "Suscríbete",
        "Nuevo curso",
        "términos y condiciones de la suscripción",
    ];
    
    let mut paragraphs: Vec<String> = Vec::new();
    for element in document.select(&p_selector) {
        let text = element.text().collect::<Vec<_>>().join(" ");
        let trimmed = text.trim().to_string();
        
        // Check if this paragraph contains an end marker
        if let Some(marker) = end_markers.iter().find(|m| trimmed.contains(*m)) {
            // If marker found, truncate at the marker and stop
            if let Some(pos) = trimmed.find(marker) {
                let truncated = trimmed[..pos].trim().to_string();
                if truncated.len() >= 20 {
                    paragraphs.push(truncated);
                }
            }
            break; // Stop processing more paragraphs
        }
        
        // No marker found, add the paragraph if it's long enough
        if trimmed.len() >= 20 {
            paragraphs.push(trimmed);
        }
    }
    
    paragraphs.join("\n\n")
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse(env: Env, html: String, base_url: Option<String>) -> Result<Term, Error> {
    let url = base_url.as_ref().map(|s| s.as_str());
    let is_elpais = url.map(|u| u.contains("elpais.com")).unwrap_or(false);

    // For El País, extract title from the full document first (before extracting body)
    let extracted_title: Option<String> = if is_elpais {
        let document = Html::parse_document(&html);
        let mut title: Option<String> = None;
        
        // Try multiple selectors for El País title
        // 1. Try h1 within article header region
        if let Ok(header_selector) = Selector::parse("[data-dtm-region=\"articulo_cabecera\"] h1") {
            if let Some(h1) = document.select(&header_selector).next() {
                let title_text = h1.text().collect::<String>();
                let trimmed = title_text.trim();
                if !trimmed.is_empty() {
                    title = Some(trimmed.to_string());
                }
            }
        }
        
        // 2. Try h1 directly (fallback if header region didn't work)
        if title.is_none() {
            if let Ok(h1_selector) = Selector::parse("h1") {
                for h1 in document.select(&h1_selector) {
                    let title_text = h1.text().collect::<String>();
                    let trimmed = title_text.trim();
                    // Filter out navigation/UI h1s (usually short or contain specific text)
                    if !trimmed.is_empty() 
                        && trimmed.len() > 20 
                        && !trimmed.eq_ignore_ascii_case("EL PAÍS")
                        && !trimmed.contains("Seleccione")
                        && !trimmed.contains("suscríbete") {
                        title = Some(trimmed.to_string());
                        break;
                    }
                }
            }
        }
        
        title
    } else {
        None
    };

    // For El País, extract from the article body region in the original HTML first
    let html_to_parse = if is_elpais {
        if let Ok(region_selector) = Selector::parse("[data-dtm-region=\"articulo_cuerpo\"]") {
            let document = Html::parse_document(&html);
            if let Some(article_body) = document.select(&region_selector).next() {
                // Extract the HTML of the article body region
                article_body.html().as_str().to_string()
            } else {
                html // Fallback to original HTML if region not found
            }
        } else {
            html
        }
    } else {
        html
    };

    // Create ReadabilityOptions with default settings
    let mut options = readabilityrs::ReadabilityOptions::default();
    options.disable_json_ld = false;

    match readabilityrs::Readability::new(&html_to_parse, url, Some(options)) {
        Ok(readability) => {
            match readability.parse() {
                Some(article) => {
                    let mut map = rustler::types::map::map_new(env);

                    // Add title - use extracted title for El País if available, otherwise use readability title
                    let title_term = if let Some(title) = extracted_title {
                        title.encode(env)
                    } else {
                        match article.title.as_ref() {
                            Some(title) => title.encode(env),
                            None => rustler::types::atom::nil().encode(env),
                        }
                    };
                    map = map
                        .map_put(Atom::from_str(env, "title")?.encode(env), title_term)
                        .map_err(|_| Error::BadArg)?;

                    // Add content (extract only paragraph text, return as plain text)
                    let content_term = match article.content.as_ref() {
                        Some(content) => {
                            let paragraph_text = extract_paragraph_text(content, url);
                            if paragraph_text.is_empty() {
                                rustler::types::atom::nil().encode(env)
                            } else {
                                paragraph_text.encode(env)
                            }
                        }
                        None => rustler::types::atom::nil().encode(env),
                    };
                    map = map
                        .map_put(Atom::from_str(env, "content")?.encode(env), content_term)
                        .map_err(|_| Error::BadArg)?;

                    // Add excerpt (can be nil)
                    let excerpt_term = match article.excerpt.as_ref() {
                        Some(excerpt) => excerpt.encode(env),
                        None => rustler::types::atom::nil().encode(env),
                    };
                    map = map
                        .map_put(Atom::from_str(env, "excerpt")?.encode(env), excerpt_term)
                        .map_err(|_| Error::BadArg)?;

                    // Add author (using byline field)
                    let author_term = match article.byline.as_ref() {
                        Some(byline) => byline.encode(env),
                        None => rustler::types::atom::nil().encode(env),
                    };
                    map = map
                        .map_put(Atom::from_str(env, "author")?.encode(env), author_term)
                        .map_err(|_| Error::BadArg)?;

                    // Add length (of extracted paragraph text)
                    let content_len = match article.content.as_ref() {
                        Some(content) => extract_paragraph_text(content, url).len(),
                        None => 0,
                    };
                    map = map
                        .map_put(
                            Atom::from_str(env, "length")?.encode(env),
                            (content_len as i64).encode(env),
                        )
                        .map_err(|_| Error::BadArg)?;

                    Ok(map.encode(env))
                }
                None => Err(Error::Term(Box::new("No article content found".to_string()))),
            }
        }
        Err(e) => Err(Error::Term(Box::new(format!("Readability error: {}", e)))),
    }
}
