"""CLI frontend for headless RAG queries."""

import sys
from rag import generate_response

def main():
    print("RAG CLI Frontend started. (Type 'exit' or 'quit' to stop, Ctrl+C to abort)")
    
    while True:
        try:
            # 1. Get user input
            query = input("\nQuery: ").strip()
            if not query:
                continue
            if query.lower() in ["exit", "quit"]:
                print("Exiting...")
                break

            # 2. Call the RAG pipeline directly
            result = generate_response(query)
            
            # 3. Display the answer
            print(f"\nAnswer:\n{result['answer']}")
            
            # 4. (Optional) Display the sources used
            if result.get("sources"):
                print("\nSources cited:")
                for i, doc in enumerate(result["sources"]):
                    print(f"  [{i + 1}] {doc['source']} (Similarity: {doc['score']:.2f})")

        except (KeyboardInterrupt, EOFError):
            print("\nExiting...")
            break
        except Exception as e:
            print(f"\nError processing query: {e}")

if __name__ == "__main__":
    main()
