"""CLI frontend for headless RAG queries. Run it with:  bash start.sh cli"""

import time

from rag import generate_response


def main():
    print("RAG CLI started. Type a question, or 'exit' to stop (Ctrl+C also works).")

    while True:
        try:
            query = input("\nQuery: ").strip()
            if not query:
                continue
            if query.lower() in ("exit", "quit"):
                print("Exiting...")
                break

            print("Thinking...")
            start = time.time()
            result = generate_response(query)
            print(f"\nAnswer ({time.time() - start:.1f}s):\n{result['answer']}")

            if result.get("sources"):
                print("\nSources cited:")
                for i, doc in enumerate(result["sources"]):
                    print(f"  [{i + 1}] {doc['source']} (Similarity: {doc['score']:.2f})")

        except (KeyboardInterrupt, EOFError):
            print("\nExiting...")
            break
        except Exception as e:
            print(f"\nError: {e}")


if __name__ == "__main__":
    main()
