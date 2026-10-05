import argparse

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a reusable Foundry document assistant.")
    parser.add_argument("--endpoint", required=True, help="Foundry project endpoint.")
    parser.add_argument("--model", required=True, help="Model deployment name.")
    parser.add_argument("--name", default="document-assistant", help="Agent name.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project = AIProjectClient(endpoint=args.endpoint, credential=DefaultAzureCredential())
    agent = project.agents.create_agent(
        model=args.model,
        name=args.name,
        instructions=(
            "You are a document-processing assistant. Use indexed document content when available, "
            "state uncertainty clearly, and return concise, structured answers."
        ),
    )
    print(f"Created agent {agent.name} ({agent.id})")


if __name__ == "__main__":
    main()

