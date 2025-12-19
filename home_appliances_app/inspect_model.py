import tensorflow as tf

interpreter = tf.lite.Interpreter(model_path="e:/Desktop Files/Folders/App/home_appliances/converted_tflite/model_unquant.tflite")
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print("Input Details:")
print(input_details)
print("\nOutput Details:")
print(output_details)
