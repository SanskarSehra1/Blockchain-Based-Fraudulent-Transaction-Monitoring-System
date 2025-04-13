from flask import Flask, request, jsonify
import pickle
import numpy as np
from sklearn.preprocessing import LabelEncoder

app = Flask(__name__)

# Load the trained model
model = pickle.load(open('trained_ML_Model.pkl', 'rb'))

# Initialize the label encoder for 'reason' feature (adjust these based on your dataset)
reason_encoder = LabelEncoder()
reason_encoder.fit(['Amount exceeds limit', 'Time limit', 'Gas fee'])  

# Function to preprocess data
def preprocess(data):
    sender = data['sender']
    recipient = data['recipient']
    amount = data['amount']
    reason = data['reason']
    timestamp = data['timestamp']
    
    # Extract time-based features from timestamp
    time_of_day = (timestamp % 86400) // 3600  # Hour of the day
    day_of_week = (timestamp // 86400) % 7  # Day of the week (0-6)
    is_weekend = 1 if day_of_week in [5, 6] else 0  # Is it weekend?

    # Encode the 'reason' feature (you need to fit on all possible reasons)
    reason_encoded = encode_reason(reason)
    
    # Hash the sender and recipient addresses to convert them to numeric values
    sender_recipient_hash = hash_address(sender + recipient)
    
    # Combine all features into one array (you may need to adjust this to match the model input)
    features = np.array([
        sender_recipient_hash,  # Sender-Recipient hash
        amount,
        reason_encoded,
        time_of_day,
        day_of_week,
        is_weekend
    ])
    
    # Pad the features to ensure they match the number of features your model expects (38)
    if len(features) < 38:
        features = np.pad(features, (0, 38 - len(features)), 'constant', constant_values=0)
    
    return features

# Function to encode 'reason' feature
def encode_reason(reason):
    return reason_encoder.transform([reason])[0]

# Function to hash addresses (for sender and recipient)
def hash_address(address):
    return hash(address) % (10 ** 8)  # Simple hash, keeping the number small

@app.route('/predict', methods=['POST'])
def predict():
    # Get the incoming JSON data
    data = request.get_json()
    
    # Preprocess the data to match the trained model's input
    features = preprocess(data)
    
    # Make the prediction using the trained model
    prediction = model.predict([features])
    
    # Return the prediction result as JSON
    return jsonify({'approval': bool(prediction[0])})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
