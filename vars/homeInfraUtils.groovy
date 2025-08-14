/**
 * Minimal Jenkins Shared Library for Testing
 * 
 * @author Jenkins CI
 * @version 1.0.0-test
 */

/**
 * Simple test method to verify library loading
 */
def test() {
    echo "✅ homeInfraUtils library is working!"
    return "success"
}

/**
 * Another test method
 */
def simpleTest() {
    echo "✅ simpleTest method works!"
    return "OK"
}