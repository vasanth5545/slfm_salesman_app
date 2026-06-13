import PyPDF2
import sys

def read_pdf(file_path):
    try:
        with open(file_path, 'rb') as file:
            reader = PyPDF2.PdfReader(file)
            text = ''
            for page in reader.pages:
                text += page.extract_text() + '\n'
            return text
    except Exception as e:
        return str(e)

file1 = r"C:\Users\LENOVO\Downloads\Vasanth Resume.pdf"
file2 = r"C:\Users\LENOVO\Downloads\CV Vasanth.pdf"

with open("pdf_output.txt", "w", encoding="utf-8") as f:
    f.write("--- FILE 1 ---\n")
    f.write(read_pdf(file1) + "\n")
    f.write("--- FILE 2 ---\n")
    f.write(read_pdf(file2) + "\n")
