using SkladKomforta.Application.Kanban;

namespace SkladKomforta.Application.Company;

public sealed record DocumentLayoutCategory(Guid CategoryId, string Name,
    IReadOnlyList<KanbanFieldSummary> Fields, IReadOnlyList<string>? FieldCodes);
public sealed record DocumentLayoutBoard(Guid WorkflowId, string Name, string Specialization,
    IReadOnlyList<DocumentLayoutCategory> Categories, DocumentTemplate? Template = null);
public sealed record SaveDocumentLayout(IReadOnlyList<DocumentLayoutSelection> Categories, DocumentTemplate? Template = null);
public sealed record DocumentLayoutSelection(Guid CategoryId, IReadOnlyList<string>? FieldCodes);
public sealed record DocumentColumn(string Code, string Label);

public interface IDocumentLayoutService
{
    Task<IReadOnlyList<DocumentLayoutBoard>> GetAsync(CancellationToken token);
    Task SaveAsync(Guid actorId, Guid workflowId, SaveDocumentLayout request, CancellationToken token);
    Task<IReadOnlyDictionary<Guid, IReadOnlyList<KanbanFieldSummary>>> GetFieldsAsync(Guid workflowId, CancellationToken token);
    Task<DocumentTemplate?> GetTemplateAsync(Guid workflowId, CancellationToken token);
}
