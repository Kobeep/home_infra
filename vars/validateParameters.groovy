#!/usr/bin/env groovy

/**
 * Validate required parameters for a pipeline
 * @param params Map of parameters to validate
 * @param required List of required parameter names
 */
def call(Map params, List<String> required) {
    def missing = []
    
    required.each { param ->
        if (!params.containsKey(param) || !params[param] || params[param].toString().trim().isEmpty()) {
            missing.add(param)
        }
    }
    
    if (!missing.isEmpty()) {
        error "❌ Missing required parameters: ${missing.join(', ')}"
    }
    
    echo "✅ All required parameters validated"
}